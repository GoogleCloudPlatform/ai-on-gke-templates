apiVersion: apps/v1
kind: Deployment
metadata:
  name: latency-profile-generator
  namespace: ${namespace}
  labels:
    name: latency-profile-generator
spec:
  selector:
    matchLabels:
      name: latency-profile-generator
  template:
    metadata:
      labels:
        name: latency-profile-generator
    spec:
      serviceAccountName: ${latency_profile_kubernetes_service_account}
      containers:
        - name: latency-profile-generator
          image: ${artifact_registry}/latency-profile:latest
          command: ["bash", "-c", "./latency_throughput_curve.sh"]
          env:
            - name: MODELS
              value: ${models}
            - name: TOKENIZER
              value: ${tokenizer}
            - name: IP
              value: ${inference_server_service}
            - name: PORT
              value: ${inference_server_service_port}
            - name: BACKEND
              value: ${inference_server_framework}
            - name: PROMPT_DATASET
              value: ${prompt_dataset}
            - name: INPUT_LENGTH
              value: ${max_prompt_len}
            - name: OUTPUT_LENGTH
              value: ${max_output_len}
            - name: REQUEST_RATES
              value: ${request_rates}
            - name: REQUEST_TIMEOUT
              value: ${request_timeout}
            - name: BENCHMARK_TIME_SECONDS
              value: ${benchmark_time_seconds}
            - name: OUTPUT_BUCKET
              value: ${output_bucket}
            - name: OUTPUT_BUCKET_FILEPATH
              value: ${output_bucket_filepath}
            - name: SCRAPE_SERVER_METRICS
              value: ${scrape_server_metrics}
            - name: MAX_NUM_PROMPTS
              value: ${max_num_prompts}
            - name: FILE_PREFIX
              value: ${file_prefix}
            - name: SAVE_AGGREGATED_RESULT
              value: ${save_aggregated_result}
            - name: STREAM_REQUEST
              value: ${stream_request}
%{ for hugging_face_token_secret in hugging_face_token_secret_list ~}
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: HF_TOKEN
%{ endfor ~}
%{ for hf_token in k8s_hf_secret_list ~}
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: HF_TOKEN
%{ endfor ~}