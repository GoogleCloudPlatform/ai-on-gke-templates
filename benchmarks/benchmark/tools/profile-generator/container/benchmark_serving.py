r"""Benchmark LLM serving throughput and latency.
This script is for sending requests with prompts to LLM server and benchmark
the latency and throughput at various request rates. It is a modified version of
https://github.com/vllm-project/vllm/blob/main/benchmarks/benchmark_serving.py.
It currently supports TGI, vLLM, Triton TensorRT-LLM and Saxml.
"""

import argparse
import asyncio
from datetime import datetime
import json
import random
import requests
import time
from typing import AsyncGenerator, List, Optional, Tuple, Dict
from prometheus_client import start_http_server, Histogram, Gauge

import google.auth
import google.auth.transport.requests
from google.cloud import storage

import aiohttp
import numpy as np
from transformers import AutoTokenizer
from transformers import PreTrainedTokenizerBase

from google.protobuf.timestamp_pb2 import Timestamp

MIN_SEQ_LEN = 4
CLIENT_TIMEOUT_SEC = 3 * 60 * 60
NEW_TEXT_KEY = "\nOutput:\n"
PROMETHEUS_PORT = 9090

# Prometheus Metrics
prompt_length_metric = Histogram("LatencyProfileGenerator:prompt_length", "Input prompt length", buckets=[2**i for i in range(1, 16)])
response_length_metric = Histogram("LatencyProfileGenerator:response_length", "Response length", buckets=[2**i for i in range(1, 16)])
request_latency_per_output_token_metric = Histogram('LatencyProfileGenerator:request_latency_per_output_token', 'Time per output token per request (including first token)')
tpot_metric = Histogram('LatencyProfileGenerator:time_per_output_token', 'Time per output token per request (excluding first token)')
ttft_metric = Histogram('LatencyProfileGenerator:time_to_first_token', 'Time to first token per request')
active_requests_metric = Gauge('LatencyProfileGenerator:active_requests', 'How many requests actively being processed')

class ErrorsReport():
  ClientConnectorErrors: int
  TimeoutErrors: int
  ContentTypeErrors: int
  ClientOSErrors: int
  ServerDisconnectedErrors: int
  unknown_errors: int

  def __init__(self):
    self.ClientConnectorErrors = 0
    self.TimeoutErrors = 0
    self.ContentTypeErrors = 0
    self.ClientOSErrors = 0
    self.ServerDisconnectedErrors = 0
    self.unknown_errors = 0

  
  def to_dict(self) -> dict:
    return {k: v for k, v in self.__dict__.items() if isinstance(v, int)}

  def record_error(self, error: Exception):
      if isinstance(error, aiohttp.client_exceptions.ClientConnectorError):
          self.ClientConnectorErrors += 1
          print(f"ClientConnectorError: {error}")
      elif isinstance(error, asyncio.TimeoutError):
          self.TimeoutErrors += 1
          print(f"TimeoutError: {error}")
      elif isinstance(error, aiohttp.client_exceptions.ContentTypeError):
          self.ContentTypeErrors += 1
          print(f"ContentTypeError: {error}")
      elif isinstance(error, aiohttp.client_exceptions.ClientOSError):
          self.ClientOSErrors += 1
          print(f"ClientOSError: {error}")
      elif isinstance(error, aiohttp.client_exceptions.ServerDisconnectedError):
          self.ServerDisconnectedErrors += 1
          print(f"ServerDisconnectedError: {error}")
      else:
          self.unknown_errors += 1
          print(f"Unknown error: {error}")

  def append_report(self, report: "ErrorsReport"):
      self.ClientConnectorErrors += report.ClientConnectorErrors
      self.TimeoutErrors += report.TimeoutErrors
      self.ContentTypeErrors += report.ContentTypeErrors
      self.ClientOSErrors += report.ClientOSErrors
      self.ServerDisconnectedErrors += report.ServerDisconnectedErrors
      self.unknown_errors += report.unknown_errors

# Add trace config for monitoring in flight requests
async def on_request_start(session, trace_config_ctx, params):
    active_requests_metric.inc()

async def on_request_end(session, trace_config_ctx, params):
    active_requests_metric.dec()

trace_config = aiohttp.TraceConfig()
trace_config.on_request_start.append(on_request_start)
trace_config.on_request_end.append(on_request_end)

# Google Cloud Storage Client
gcs_client = None
gcs_bucket = None

def get_filtered_dataset(
    dataset_path: str,
    max_input_len: int,
    max_output_len: int,
    tokenizer: PreTrainedTokenizerBase,
    use_dummy_text: bool,
) -> List[Tuple[str, int, int]]:
  """Samples requests from the dataset or creates dummy requests."""
  if use_dummy_text:
    dummy_prompt_token_ids = [0] * max_input_len
    dummy_prompt = tokenizer.decode(dummy_prompt_token_ids)
    return [(
          dummy_prompt,
          max_input_len,
          max_output_len,
    )]

  # Load the dataset.
  with open(dataset_path) as f:
    dataset = json.load(f)
  # Filter out the conversations with less than 2 turns.
  dataset = [data for data in dataset if len(data["conversations"]) >= 2]
  # Only keep the first two turns of each conversation.
  dataset = [
      (data["conversations"][0]["value"], data["conversations"][1]["value"])
      for data in dataset
  ]

  # Tokenize the prompts and completions.
  prompts = [prompt for prompt, _ in dataset]
  prompt_token_ids = tokenizer(prompts).input_ids
  completions = [completion for _, completion in dataset]
  completion_token_ids = tokenizer(completions).input_ids
  tokenized_dataset = []
  for i in range(len(dataset)):
    output_len = len(completion_token_ids[i])
    tokenized_dataset.append((prompts[i], prompt_token_ids[i], output_len))

  # Filter out too long sequences.
  filtered_dataset: List[Tuple[str, int, int]] = []
  for prompt, prompt_token_ids, output_len in tokenized_dataset:
    prompt_len = len(prompt_token_ids)
    if prompt_len < MIN_SEQ_LEN or output_len < MIN_SEQ_LEN:
      # Prune too short sequences.
      # This is because TGI causes errors when the input or output length
      # is too short.
      continue
    if prompt_len > max_input_len or output_len > max_output_len:
      # Prune too long sequences.
      continue
    filtered_dataset.append((prompt, prompt_len, output_len))

  return filtered_dataset

async def generate_next_request(
    input_requests: List[Tuple[str, int, int]],
    request_rate: float,
) -> AsyncGenerator[Tuple[str, int, int], None]:
  """Gets request async."""
  while True:
    request = random.choice(input_requests)
    yield request

    if request_rate == float("inf"):
      # If the request rate is infinity, then we don't need to wait.
      continue
    # Sample the request interval from the exponential distribution.
    interval = np.random.exponential(1.0 / request_rate)
    # The next request will be sent after the interval.
    await asyncio.sleep(interval)

async def send_stream_request(
    backend: str,
    api_url: str,
    prompt: str,
    prompt_len: int,
    output_len: int,
    best_of: int,
    use_beam_search: bool,
    top_k: int,
    tokenizer: PreTrainedTokenizerBase,
    sax_model: str,
    model: str,
) -> Tuple[Tuple[int, int, float], float, Optional[ErrorsReport]]:
  """Sends stream request to server"""
  request_start_time = time.time()
  errors = ErrorsReport()

  headers = {"User-Agent": "Benchmark Client"}
  if backend == "vllm":
    pload = {
        "model": model,
        "prompt": prompt,
        "n": 1,
        "best_of": best_of,
        "use_beam_search": use_beam_search,
        "temperature": 0.0 if use_beam_search else 1.0,
        "top_p": 1.0,
        "max_tokens": output_len,
        "ignore_eos": True,
        "stream": True,
    }
  elif backend == "jetstream":
    pload = {
        "prompt": prompt,
        "max_tokens": output_len,
        "stream": True,
    }
  else: 
    raise ValueError(f"Unknown backend: {backend}")

  ttft = 0.0
  st = time.perf_counter()
  output = ""
  timeout = aiohttp.ClientTimeout(total=CLIENT_TIMEOUT_SEC)
  async with aiohttp.ClientSession(timeout=timeout,trust_env=True) as session:
    try:
      async with session.post(api_url, headers=headers, json=pload, ssl=False) as response:
        async for chunk_bytes in response.content.iter_chunks():
          chunk_bytes = chunk_bytes[0].strip()
          if not chunk_bytes:
              continue
          timestamp = time.perf_counter()
          # First token
          if ttft == 0.0:
            ttft = timestamp - st
          if backend == "vllm":
            if chunk_bytes.decode("utf-8")[6:] != "[DONE]":
              output += json.loads(chunk_bytes.decode("utf-8")[6:])["choices"][0]["text"]
          elif backend == "jetstream":
            if chunk_bytes.decode("utf-8") != "":
              output += json.loads(chunk_bytes.decode("utf-8"))["text"]
    except Exception as e:
      errors.record_error(e)
      return None, None, errors
  request_end_time = time.time()
  output_token_ids = tokenizer(output).input_ids
  output_len = len(output_token_ids)
  request_latency = (prompt_len, output_len, (request_end_time - request_start_time))

  # Exclude first token for tpot calculation
  if output_len > 1:
    tpot_metric.observe((request_end_time - ttft - request_start_time) / (output_len - 1))
  request_latency_per_output_token_metric.observe((request_end_time - request_start_time) / output_len)
  if ttft is not None:
    ttft_metric.observe(ttft)
  prompt_length_metric.observe(prompt_len)
  response_length_metric.observe(output_len)
  return request_latency, ttft, None

async def send_request(
    backend: str,
    api_url: str,
    prompt: str,
    prompt_len: int,
    output_len: int,
    best_of: int,
    use_beam_search: bool,
    top_k: int,
    tokenizer: PreTrainedTokenizerBase,
    sax_model: str,
    model: str,
) -> Tuple[Tuple[int, int, float], float, Optional[ErrorsReport]]:
  """Sends request to server."""
  request_start_time = time.time()
  errors = ErrorsReport()

  headers = {"User-Agent": "Benchmark Client"}
  if backend == "vllm":
    pload = {
        "model": model,
        "prompt": prompt,
        "n": 1,
        "best_of": best_of,
        "use_beam_search": use_beam_search,
        "temperature": 0.0 if use_beam_search else 1.0,
        "top_p": 1.0,
        "max_tokens": output_len,
        "ignore_eos": False,
        "stream": False,
    }
  elif backend == "tgi":
    assert not use_beam_search
    params = {
        "best_of": best_of,
        "max_new_tokens": output_len,
        "do_sample": True,
    }
    pload = {
        "inputs": prompt,
        "parameters": params,
    }
  elif backend == "naive_transformers":
    # If max_length or top_k is not specified _MAX_LENGTH_DEFAULT = 200 and
    # _TOP_K_DEFAULT = 10 in peft/handler.py will be used.
    pload = {
        "instances": [{
            "prompt": prompt,
            "max_length": output_len,
            "top_k": top_k,
        }]
    }
  elif backend == "tensorrt_llm_triton":
    pload = {
        "text_input": prompt,
        "max_tokens": output_len,
        "beam_width": 1 if not use_beam_search else best_of,
        "temperature": 0.0 if use_beam_search else 1.0,
        "top_p": 1.0,
        "bad_words": "",
        "stop_words": "",
        "stream": False,
    }
  elif backend == "sax":
    pload = {
        "model": sax_model,
        "prompt": prompt,
        "n": 1,
        "best_of": best_of,
        "use_beam_search": use_beam_search,
        "temperature": 0.0 if use_beam_search else 1.0,
        "top_p": 1.0,
        "top_k": 50,
        "max_tokens": output_len,
        "stream": False,
    }
  elif backend == "jetstream":
    pload = {
        "prompt": prompt,
        "max_tokens": output_len,
    }
  else:
    raise ValueError(f"Unknown backend: {backend}")

  # Set client timeout to be 3 hrs.
  timeout = aiohttp.ClientTimeout(total=CLIENT_TIMEOUT_SEC)
  async with aiohttp.ClientSession(timeout=timeout,trust_env=True,trace_configs=[trace_config]) as session:
    while True:
      try:
        async with session.post(api_url, headers=headers, json=pload, ssl=False) as response:
          output = await response.json()

        # Re-send the request if it failed.
        if "error" not in output:
          break
      except Exception as e:
        errors.record_error(e)
        return None, None, errors

  request_end_time = time.time()
  # Naive HF transformers generation and TensorRT-LLM generation stops at EOS
  # tokens and the generation may be shorter than the ground-truth output
  # sequence length.
  if backend == "naive_transformers":
    complete_pred = output["predictions"][0][0]["generated_text"]
    new_text_start_index = complete_pred.find(NEW_TEXT_KEY) + len(NEW_TEXT_KEY)
    pred = complete_pred[new_text_start_index:]
    output_token_ids = tokenizer(pred).input_ids
    output_len = len(output_token_ids) - prompt_len
  elif backend == "tensorrt_llm_triton":
    output_token_ids = tokenizer(output["text_output"]).input_ids
    output_len = len(output_token_ids)
  elif backend == "sax":
    output_token_ids = tokenizer(output["choices"][0]["text"]).input_ids
    output_len = len(output_token_ids)
  elif backend == "tgi":
    output_token_ids = tokenizer(output["generated_text"]).input_ids
    output_len = len(output_token_ids)
  elif backend == "vllm":
    output_token_ids = tokenizer(output["choices"][0]["text"]).input_ids
    output_len = len(output_token_ids)
  elif backend == "jetstream":
    output_token_ids = tokenizer(output["response"]).input_ids
    output_len = len(output_token_ids)

  # (prompt len, output len, latency, success)
  request_latency = (prompt_len, output_len, (request_end_time - request_start_time))
  request_latency_per_output_token_metric.observe((request_end_time - request_start_time) / output_len)
  prompt_length_metric.observe(prompt_len)
  response_length_metric.observe(output_len)

  return request_latency, None, None

async def benchmark(
    args: argparse.Namespace, 
    api_url: str,
    tokenizer: PreTrainedTokenizerBase,
    model: str,
) -> Tuple[List[Tuple[int, int, float]], List[float], Optional[ErrorsReport]]:
  """Runs benchmark with asynchronous requests."""
  input_requests = get_filtered_dataset(
      args.dataset,
      args.max_input_length,
      args.max_output_length,
      tokenizer,
      args.use_dummy_text,
  )
  benchmark_start_time = time.time()
  tasks: List[asyncio.Task] = []
  prompts_sent: int = 0
  async for request in generate_next_request(input_requests, args.request_rate):
    if args.num_prompts <= prompts_sent:
      break
    prompt, prompt_len, output_len = request
    if args.stream_request:
      task = asyncio.create_task(
        send_stream_request(
            args.backend,
            api_url,
            prompt,
            prompt_len,
            output_len,
            args.best_of,
            args.use_beam_search,
            args.top_k,
            tokenizer,
            args.sax_model,
            model,
        )
      )
    else: 
      task = asyncio.create_task(
      send_request(
          args.backend,
          api_url,
          prompt,
          prompt_len,
          output_len,
          args.best_of,
          args.use_beam_search,
          args.top_k,
          tokenizer,
          args.sax_model,
          model,
        )
      )
    tasks.append(task)
    prompts_sent += 1
  results = await asyncio.gather(*tasks)
  combined_latencies = []
  combined_ttfts = []
  combined_errors = ErrorsReport()
  for latency, ttft, errors in results:
    if latency:
      combined_latencies.append(latency)
    if errors:
      combined_errors.append_report(errors)
    if ttft:
      combined_ttfts.append(ttft)
  
  benchmark_duration = time.time() - benchmark_start_time
  print_and_save_result(args, benchmark_duration, prompts_sent, model, combined_latencies, combined_ttfts, combined_errors)
  return combined_latencies, combined_ttfts, combined_errors

def save_json_results(args: argparse.Namespace, benchmark_result, server_metrics, model, errors):
  # Setup
  start_dt_proto = Timestamp()
  start_dt_proto.FromDatetime(args.start_datetime)

  final_json = {
    # metrics values are numerical
    "metrics" : {
      # Traffic
      "num_prompts_attempted": benchmark_result['num_prompts_attempted'],
      "num_prompts_succeeded": benchmark_result['num_prompts_succeeded'],
      "request_rate": args.request_rate,
      'server_metrics': {
        **server_metrics
      },
      **benchmark_result,
      **(errors.to_dict()),
    },
    # dimensions values are strings
    "dimensions": {
      "date": args.start_datetime.strftime('%Y%m%d-%H%M%S'),
      "backend": args.backend,
      "model_id": model,
      "tokenizer_id": args.tokenizer,
      **(json.loads(args.additional_metadata_metrics_to_save) if args.additional_metadata_metrics_to_save else {})
    },
    "config": {
      "model": model,
      "num_models": len(args.models.split(',')),
      "model_server": args.backend,
      "start_time": {
        "seconds" : start_dt_proto.seconds,
        "nanos" : start_dt_proto.nanos
      }
    },
    "summary_stats": {
      "stats": [{
        "request_rate": args.request_rate,
        "request_latency": {
          "mean": benchmark_result["avg_latency"],
          "median": benchmark_result["median_latency"],
          "sd": benchmark_result["sd_latency"],
          "min": benchmark_result["min_latency"],
          "max": benchmark_result["max_latency"],
          "p90": benchmark_result["p90_latency"],
          "p99": benchmark_result["p99_latency"],
        },
        "throughput": {
          "mean": benchmark_result['throughput']
        },
        "input_length": {
          "mean": benchmark_result["avg_input_len"],
          "median": benchmark_result["median_input_len"],
          "sd": benchmark_result["sd_input_len"],
          "min": benchmark_result["min_input_len"],
          "max": benchmark_result["max_input_len"],
          "p90": benchmark_result["p90_input_len"],
          "p99": benchmark_result["p99_input_len"],
        },
        "output_length": {
          "mean": benchmark_result["avg_output_len"],
          "median": benchmark_result["median_output_len"],
          "sd": benchmark_result["sd_output_len"],
          "min": benchmark_result["min_output_len"],
          "max": benchmark_result["max_output_len"],
          "p90": benchmark_result["p90_output_len"],
          "p99": benchmark_result["p99_output_len"],
        },
        "tpot": {
          "mean": benchmark_result["avg_per_output_token_latency"],
          "median": benchmark_result["median_per_output_token_latency"],
          "sd": benchmark_result["sd_per_output_token_latency"],
          "min": benchmark_result["min_per_output_token_latency"],
          "max": benchmark_result["max_per_output_token_latency"],
          "p90": benchmark_result["p90_per_output_token_latency"],
          "p99": benchmark_result["p99_per_output_token_latency"],
        },
        "model_server_metrics" : [{"Name": name, **metrics} for name, metrics in server_metrics.items()]
      }]
    }
  }
  
  # Save to file
  model_without_slash = model.replace("/","-")
  file_name = (
      f"{args.file_prefix}-{args.backend}-{args.request_rate}qps-{args.start_datetime.strftime('%Y%m%d-%H%M%S')}-{model_without_slash}.json"
  )
  with open(file_name, "w", encoding="utf-8") as outfile:
    json.dump(final_json, outfile)
  if gcs_bucket is not None:
    gcs_bucket.blob(f"{args.output_bucket_filepath}/{file_name}").upload_from_filename(file_name)
    print(f"File {file_name} uploaded to gs://{args.output_bucket}/{args.output_bucket_filepath}")

def metrics_to_scrape(backend: str) -> List[str]:
  # Each key in the map is a metric, it has a corresponding 'stats' object
  # It must be populated on the outputs 'metrics' field as 'key':'stats'
  # If a value is specified for a given key, it will be populated on the outputs `summary_stats.stats` field as 'value':'stats' as well.
  if backend == "vllm":
    return ["vllm:gpu_cache_usage_perc", "vllm:num_requests_waiting"]
  elif backend == "jetstream":
    return [
      "jetstream_slots_used_percentage",
      "jetstream_prefill_backlog_size",
    ]
  else:
    return []

def print_metrics(metrics: List[str], duration: float, backend: str):
  # Creates a credentials object from the default service account file
  # Assumes that script has appropriate default credentials set up, ref:
  # https://googleapis.dev/python/google-auth/latest/user-guide.html#application-default-credentials
  credentials, project_id = google.auth.default()
  # Prepare an authentication request - helps format the request auth token
  auth_req = google.auth.transport.requests.Request()

  server_metrics = {}

  # Request refresh tokens
  credentials.refresh(auth_req)
  url='https://monitoring.googleapis.com/v1/projects/%s/location/global/prometheus/api/v1/metadata' % (project_id)
  headers_api = {'Authorization': 'Bearer ' + credentials.token}
  request_post = requests.get(url=url, headers=headers_api)
  all_metrics_metadata = request_post.json()
  if request_post.ok is not True:
    print("HTTP Error: %s" % (all_metrics_metadata))
  if all_metrics_metadata["status"] != "success":
    print("Metadata error response: %s" % all_metrics_metadata["error"])

  for metric in metrics:
    print("Metric Name: %s" % (metric))

    # Find metric type
    metric_type = all_metrics_metadata['data'][metric]
    if all_metrics_metadata['data'][metric] is None:
      print("No metric found for: %s" % metric)
      return
    metric_type = metric_type[0]['type']

    metric_results = {}
    # Queries scrape all metrics collected from the last $DURATION seconds from the backend's related
    # podmonitoring spec assumed to be named "$BACKEND-podmonitoring"
    queries = {
      "gauge": {
        "Mean": "avg_over_time(%s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "Median": "quantile_over_time(0.5, %s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "Sd": "stddev_over_time(%s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "Min": "min_over_time(%s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "Max": "max_over_time(%s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "P90": "quantile_over_time(0.9, %s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
        "P99": "quantile_over_time(0.99, %s{job='%s-podmonitoring'}[%.0fs])" % (metric, backend, duration),
    },
      "histogram": {
        "Mean": "sum(rate(%s_sum{job='%s-podmonitoring'}[%.0fs])) / sum(rate(%s_count{job='%s-podmonitoring'}[%.0fs]))" % (metric, backend, duration, metric, backend, duration),
        "Median": "histogram_quantile(0.5, sum(rate(%s_bucket{job='%s-podmonitoring'}[%.0fs])) by (le))" % (metric, backend, duration),
        "Min": "histogram_quantile(0, sum(rate(%s_bucket{job='%s-podmonitoring'}[%.0fs])) by (le))" % (metric, backend, duration),
        "Max": "histogram_quantile(1, sum(rate(%s_bucket{job='%s-podmonitoring'}[%.0fs])) by (le))" % (metric, backend, duration),
        "P90": "histogram_quantile(0.9, sum(rate(%s_bucket{job='%s-podmonitoring'}[%.0fs])) by (le))" % (metric, backend, duration),
        "P99": "histogram_quantile(0.99, sum(rate(%s_bucket{job='%s-podmonitoring'}[%.0fs])) by (le))" % (metric, backend, duration),
    }
  }
    for query_name, query in queries[metric_type].items():
      # Configure respective query
      url='https://monitoring.googleapis.com/v1/projects/%s/location/global/prometheus/api/v1/query' % (project_id)
      headers_api = {'Authorization': 'Bearer ' + credentials.token}
      params = {'query': query}
      print(f"Finding {query_name} {metric} with the following query: {query}")
      request_post = requests.get(url=url, headers=headers_api, params=params)
      response = request_post.json()

      print(f"Got response from metrics server: {response}")

      # handle response
      if request_post.ok:
        if response["status"] == "success":
          metric_results[query_name] = float(response["data"]["result"][0]["value"][1])
          print("%s: %s" % (query_name, response["data"]["result"][0]["value"][1]))
        else:
          print("Cloud Monitoring PromQL Error: %s" % (response["error"]))
      else:
        print("HTTP Error: %s" % (response))
    server_metrics[metric] = metric_results
  return server_metrics

def get_stats_for_set(name, description, points):
  avg = np.mean(points) if points else 0
  median = np.median(points) if points else 0
  sd = np.std(points) if points else 0
  min = np.min(points) if points else 0
  max = np.max(points) if points else 0
  p90 = np.percentile(points, 90) if points else 0
  p99 = np.percentile(points, 99) if points else 0

  print(f"Average {description}:" f" {avg:.2f}")

  return {
    f'avg_{name}':  avg,
    f'median_{name}': median,
    f'sd_{name}': sd,
    f'min_{name}': min,
    f'max_{name}': max,
    f'p90_{name}': p90,
    f'p99_{name}': p99,
  }

def print_and_save_result(args: argparse.Namespace, benchmark_duration, total_requests, model, request_latencies, ttfts, errors):
  benchmark_result = {}

  print(f"====Result for Model: {model}====")
  print(f"Errors: {errors.to_dict()}")
  print(f"Total time: {benchmark_duration:.2f} s")
  print(f"Successful/total requests: {len(request_latencies)}/{total_requests}")
  print(f"Requests/min: {60 * total_requests / benchmark_duration:.2f}")
  benchmark_result["num_prompts_attempted"] = total_requests
  benchmark_result["num_prompts_succeeded"] = len(request_latencies)
  benchmark_result['benchmark_time'] = benchmark_duration
  benchmark_result['throughput_rps'] = (args.num_prompts / benchmark_duration)

  total_output_tokens = np.sum([output_len for _, output_len, _ in
                                request_latencies])
  output_tokens_per_second = total_output_tokens / benchmark_duration
  benchmark_result['throughput'] = output_tokens_per_second

  output_tokens_per_min = 60 * output_tokens_per_second
  print(f"Output_tokens/min: {output_tokens_per_min:.2f}")
  benchmark_result['total_output_token'] = int(total_output_tokens)
  benchmark_result['output_tokens_per_min'] = output_tokens_per_min

  total_input_tokens = np.sum([prompt_len for prompt_len, _, _ in
                               request_latencies])
  input_tokens_per_min = 60 * total_input_tokens / benchmark_duration
  print(f"Input_tokens/min: {input_tokens_per_min:.2f}")
  benchmark_result['total_input_tokens'] = int(total_input_tokens)
  benchmark_result['input_tokens_per_min'] = input_tokens_per_min

  total_tokens = total_input_tokens + total_output_tokens
  tokens_per_min = 60 * total_tokens / benchmark_duration
  print(f"Tokens/min: {tokens_per_min:.2f}")
  benchmark_result['total_tokens'] = int(total_tokens)
  benchmark_result['tokens_per_min'] = tokens_per_min
  ttft_stats = {}
  if args.stream_request:
    ttft_stats = get_stats_for_set("TTFT", "Time to First Token (s)", ttfts)
  if args.machine_cost:
    print(
        "Cost $/1k tokens:"
        f" {args.machine_cost * 1000 / (60 * output_tokens_per_min)}"
    )

  benchmark_result = {
    **benchmark_result,
    **(get_stats_for_set("per_token_latency", "seconds/token (includes waiting time on server)", [
      latency / (prompt_len + output_len)
      for prompt_len, output_len, latency in request_latencies
    ])),
    **ttft_stats,
    # NOTE: The latency below includes requests awaiting time on server side.
    # It's not comparable with the model inference latency for batch size 1.
    **(get_stats_for_set("latency", "milliseconds/request (includes waiting time on server)" ,[1000 * latency for _, _, latency in request_latencies])),
    **(get_stats_for_set("per_output_token_latency", "milliseconds/output_token (includes waiting time on server)", [1000 * latency / output_len for _, output_len, latency in request_latencies])),
    **(get_stats_for_set("input_len", "input length", [float(prompt_len) for prompt_len, _, _ in request_latencies])),
    **(get_stats_for_set("output_len", "output length", [float(output_len) for _, output_len, _ in request_latencies]))
  }

  server_metrics = {}
  if args.scrape_server_metrics:
    server_metrics = print_metrics(metrics_to_scrape(args.backend), benchmark_duration, args.backend)
  if args.save_json_results:
    save_json_results(args, benchmark_result, server_metrics, model, errors)

async def main(args: argparse.Namespace):
  print(args)
  models = args.models.split(',')
  print(f"Models to benchmark: {models}")
  random.seed(args.seed)
  np.random.seed(args.seed)
  endpoint = (
    "v1/completions"
    if args.backend == "vllm"
    else args.endpoint
)
  
  # Create GCS client before benchmarking
  # Should fail fast if client is misconfigured or missing permissions
  if args.output_bucket is not None:
    global gcs_client
    gcs_client = storage.Client()
    global gcs_bucket
    gcs_bucket = gcs_client.bucket(args.output_bucket)

    if args.output_bucket_filepath:
      blob = gcs_bucket.blob(args.output_bucket_filepath)
      if not blob.exists():
        blob.upload_from_string('')

  print(f"Starting Prometheus Server on port {PROMETHEUS_PORT}")
  start_http_server(PROMETHEUS_PORT)

  api_url = f"http://{args.host}:{args.port}/{endpoint}"
  tokenizer = AutoTokenizer.from_pretrained(
      args.tokenizer, trust_remote_code=args.trust_remote_code
  )

  benchmark_start_time = time.time()
  args.start_datetime = datetime.fromtimestamp(benchmark_start_time)
  
  results = await asyncio.gather(
            *[benchmark(args, api_url, tokenizer, model) for model in models]
        )
  
  # Summarize results
  combined_latencies = []
  combined_ttfts = []
  combined_errors = ErrorsReport()
  for latencies, ttfts, errors in results:
    combined_latencies.extend(latencies)
    combined_ttfts.extend(ttfts)
    if errors:
      combined_errors.append_report(errors)
  
  benchmark_duration_all_models = time.time() - benchmark_start_time
  if args.save_aggregated_result:
    print_and_save_result(args, benchmark_duration_all_models, len(models)*args.num_prompts, f"ALL-{len(models)}-MODELS", combined_latencies, combined_ttfts, combined_errors)

if __name__ == "__main__":
  parser = argparse.ArgumentParser(
      description="Benchmark the online serving throughput."
  )
  parser.add_argument(
      "--backend",
      type=str,
      default="vllm",
      choices=[
          "vllm",
          "tgi",
          "naive_transformers",
          "tensorrt_llm_triton",
          "sax",
          "jetstream"
      ],
  )
  parser.add_argument(
      "--sax_model",
      type=str,
      default="",
      help="Model name to send request to at API server for SAX model server.",
  )
  parser.add_argument("--file-prefix", type=str, default="benchmark")
  parser.add_argument("--endpoint", type=str, default="generate")
  parser.add_argument("--host", type=str, default="localhost")
  parser.add_argument("--port", type=int, default=7080)
  parser.add_argument("--dataset", type=str, help="Path to the dataset.")
  parser.add_argument(
    "--models",
    type=str,
    help="Comma separated list of models to benchmark.",
  )
  parser.add_argument(
    "--stream-request", 
    action="store_true",
    help="Whether to stream the request. Needed for TTFT metric",
  )
  parser.add_argument(
      "--tokenizer",
      type=str,
      required=True,
      help="Name or path of the tokenizer.",
  )
  parser.add_argument(
      "--best-of",
      type=int,
      default=1,
      help="Generates `best_of` sequences per prompt and returns the best one.",
  )
  parser.add_argument("--use-beam-search", action="store_true")
  parser.add_argument(
      "--num-prompts",
      type=int,
      default=1000,
      help="Number of prompts to process.",
  )
  parser.add_argument(
      "--max-input-length",
      type=int,
      default=1024,
      help=(
          "Maximum number of input tokens for filtering the benchmark dataset."
      ),
  )
  parser.add_argument(
      "--max-output-length",
      type=int,
      default=1024,
      help=(
          "Maximum number of input tokens for filtering the benchmark dataset."
      ),
  )
  parser.add_argument(
      "--top-k",
      type=int,
      default=32000,
      help=(
          "Number of candidate tokens that are considered at each step of the"
          " generation process. 32000 is the vocab_size of Open-LLaMA and"
          " LLaMA2 models."
      ),
  )
  parser.add_argument(
      "--request-rate",
      type=float,
      default=float("inf"),
      help=(
          "Number of requests per second. If this is inf, "
          "then all the requests are sent at time 0. "
          "Otherwise, we use Poisson process to synthesize "
          "the request arrival times."
      ),
  )
  parser.add_argument("--seed", type=int, default=int(time.time()))
  parser.add_argument(
      "--trust-remote-code",
      action="store_true",
      help="trust remote code from huggingface",
  )
  parser.add_argument(
      "--machine-cost",
      type=float,
      default=None,
      help="Machine cost per hour including accelerators (if any)",
  )
  parser.add_argument(
      "--use-dummy-text",
      action="store_true",
      help=(
          "Whether to use dummy text with length defined by max_input_length"
          " and max_output_length."
      ),
  )
  parser.add_argument(
      "--save-json-results",
      action="store_true",
      help="Whether to save benchmark results to a json file.",
  )
  parser.add_argument(
    "--output-bucket",
    type=str,
    default=None,
    help=(
      "Specifies the Google Cloud Storage bucket to which JSON-format results"
      " will be uploaded. If not provided, no upload will occur."
    )
  )
  parser.add_argument(
    "--output-bucket-filepath",
    type=str,
    default=None,
    help=(
      "Specifies the destination path within the bucket provided by"
      " --output-bucket for uploading the JSON results. This argument requires"
      " --output-bucket to be set. If not specified, results will be uploaded "
      " to the root of the bucket. If the filepath doesnt exist, it will be"
      " created for you."
    )
  )
  parser.add_argument(
    "--save-aggregated-result",
    action="store_true",
    help="Whether to aggregate results of all models and save the result.",
  )
  parser.add_argument(
      "--additional-metadata-metrics-to-save",
      type=str,
      help=(
          "Additional metadata about the workload. Should be a dictionary in"
          " the form of a string."
      ),
  )
  parser.add_argument(
      "--scrape-server-metrics",
      action="store_true",
      help="Whether to scrape server metrics.",
  )
  cmd_args = parser.parse_args()
  asyncio.run(main(cmd_args))