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

# CREATE NODEPOOLS

module "latency-profile" {
  for_each = toset(
    flatten([
      for config in toset(var.profiles.config): toset([
        for model_server_config in toset(config.model_server_configs): toset([
          for model in toset(model_server_config.models): toset([
            for model_config in toset(model_server_config.model_configs): toset([
              for accelerator in toset(model_config.accelerators): toset([
                for accelerator_config in toset(model_config.accelerator_configs): 
                  join(" ", [model, config.model_server, accelerator, accelerator_config.accelerator_count])
              ])
            ])
          ])
        ])
      ])
    ])
  )
  source = "../latency-profile"

  credentials_config                         = var.credentials_config
  namespace                                  = var.namespace
  project_id                                 = var.project_id
  ksa                                        = var.ksa
  templates_path                             = var.templates_path
  artifact_registry                          = var.artifact_registry
  build_latency_profile_generator_image      = false # Dont build image for each profile generator instance, only need to do once.
  inference_server                           = {
    deploy    = true
    name      = split(" ", each.value)[1]
    model     = split(" ", each.value)[0]
    tokenizer = "google/gemma-7b"
    service = {
      name = "maxengine-server", # inference server service name
      port = 8000
    }
    accelerator_config = {
      type  = split(" ", each.value)[2]
      count = split(" ", each.value)[3]
    }
}
  max_num_prompts                            = var.max_num_prompts
  max_output_len                             = var.max_output_len
  max_prompt_len                             = var.max_prompt_len
  request_rates                              = var.request_rates
  output_bucket                              = var.output_bucket
  latency_profile_kubernetes_service_account = var.latency_profile_kubernetes_service_account
  k8s_hf_secret                              = var.k8s_hf_secret
  hugging_face_secret                        = var.hugging_face_secret
  hugging_face_secret_version                = var.hugging_face_secret_version
}