#!/bin/bash

# Copyright 2024 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -o xtrace

export IP=$IP

huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential

if [[ "$PROMPT_DATASET" = "sharegpt" ]]; then
  PROMPT_DATASET_FILE="ShareGPT_V3_unfiltered_cleaned_split.json"
fi

PYTHON="python3"
PYTHON_OPTS="benchmark_serving.py "
for request_rate in $(echo $REQUEST_RATES | tr ',' ' '); do
  echo "Benchmaking request rate: ${request_rate}"
  # TODO: Check if profile already exists, if so then skip
  timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
  output_file="latency-profile-${timestamp}.txt"
  if [ ${request_rate} == 0 ]; then
    request_rate="inf"
    num_prompts=$MAX_NUM_PROMPTS
  else
    num_prompts=$(awk "BEGIN {print int($request_rate * $BENCHMARK_TIME_SECONDS)}")
  fi
  echo "TOTAL prompts: $num_prompts"  # Output: 8
  PYTHON_OPTS="$PYTHON_OPTS --save-json-results --host=$IP  --port=$PORT --dataset=$PROMPT_DATASET_FILE --tokenizer=$TOKENIZER --request-rate=$request_rate --backend=$BACKEND --num-prompts=$num_prompts --max-input-length=$INPUT_LENGTH --max-output-length=$OUTPUT_LENGTH --file-prefix=$FILE_PREFIX --models=$MODELS"
  if [[ "$REQUEST_TIMEOUT" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --request-timeout=$REQUEST_TIMEOUT"
  fi
  if [[ "$OUTPUT_BUCKET" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --output-bucket=$OUTPUT_BUCKET"
  fi
  if [[ "$SCRAPE_SERVER_METRICS" = "true" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --scrape-server-metrics"
  fi
  if [[ "$SAVE_AGGREGATED_RESULT" = "true" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --save-aggregated-result"
  fi
  if [[ "$STREAM_REQUEST" = "true" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --stream-request"
  fi
  if [[ "$OUTPUT_BUCKET_FILEPATH" ]]; then
    PYTHON_OPTS="$PYTHON_OPTS --output-bucket-filepath  $OUTPUT_BUCKET_FILEPATH"
  fi
  $PYTHON $PYTHON_OPTS > $output_file
  cat $output_file
  sleep 30 # wait 30 seconds before next run to ensure metrics isolation (metrics pulled every 15s)
done

export LPG_FINISHED="true"
sleep infinity