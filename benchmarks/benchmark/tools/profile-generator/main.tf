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

provider "kubernetes" {
  config_path = (
    var.credentials_config.kubeconfig == null
    ? null
    : pathexpand(var.credentials_config.kubeconfig.path)
  )
  config_context = try(
    var.credentials_config.kubeconfig.context, null
  )
  host = (
    var.credentials_config.fleet_host == null
    ? null
    : var.credentials_config.fleet_host
  )
  token = try(data.google_client_config.identity.0.access_token, null)
}

data "google_client_config" "identity" {
  count = var.credentials_config.fleet_host != null ? 1 : 0
}

resource "google_project_service" "cloudbuild" {
  count   = var.build_latency_profile_generator_image ? 1 : 0
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_on_destroy = false
}

#  ----- Manual Benchmarking -----

module "latency-profile" {
  depends_on = [resource.null_resource.build_and_push_image]
  count      = var.targets.manual != null ? 1 : 0
  source     = "./modules/latency-profile"

  credentials_config = var.credentials_config
  namespace          = var.namespace
  project_id         = var.project_id
  templates_path     = var.templates_path
  artifact_registry  = var.artifact_registry
  inference_server = {
    name      = var.targets.manual.name
    tokenizer = var.targets.manual.tokenizer
    service = {
      name = var.targets.manual.service_name
      port = var.targets.manual.service_port
    }
  }
  prompt_dataset         = var.prompt_dataset
  max_num_prompts        = var.max_num_prompts
  max_output_len         = var.max_output_len
  max_prompt_len         = var.max_prompt_len
  request_rates          = var.request_rates
  request_timeout        = var.request_timeout
  benchmark_time_seconds = var.benchmark_time_seconds
  gcs_output = {
    bucket   = var.output_bucket
    filepath = var.output_bucket_filepath
  }
  latency_profile_kubernetes_service_account = var.latency_profile_kubernetes_service_account
  k8s_hf_secret                              = var.k8s_hf_secret
  hugging_face_secret                        = var.hugging_face_secret
  hugging_face_secret_version                = var.hugging_face_secret_version
  scrape_server_metrics                      = var.scrape_server_metrics
  file_prefix                                = var.file_prefix
  save_aggregated_result                     = var.save_aggregated_result
  models                                     = var.models
  stream_request                             = var.stream_request
}