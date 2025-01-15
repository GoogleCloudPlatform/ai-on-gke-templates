/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

credentials_config = {
  kubeconfig = {
    path = "~/.kube/config"
  }
}

project_id = "your_project_id"

namespace = "benchmark"

# Latency profile generator service configuration
# set build_latency_profile_generator_image to false to save 20 min build if no rebuild needed, eg.
# build_latency_profile_generator_image      = false
latency_profile_kubernetes_service_account = "prom-frontend-sa"
output_bucket                              = "your_project_id-benchmark-output-bucket"
k8s_hf_secret                              = "hf-token"

# Benchmark configuration for Latency Profile Generator accessing inference server
request_rates          = [5, 10, 15, 20]
request_timeout        = 600
benchmark_time_seconds = 120
artifact_registry      = "your_project_artifact_registry"

# Model server configuration information
models = "your_models"
targets = {
  manual = {
    name         = "your_model_server_name"
    service_name = "your_model_server_service_name"
    service_port = "your_model_service_service_port"
    tokenizer    = "your_tokenizer"
  }
}