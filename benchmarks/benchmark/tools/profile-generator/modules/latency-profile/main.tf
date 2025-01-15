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
locals {
  templates = [
    for f in fileset(local.templates_path, "*tpl") :
    "${local.templates_path}/${f}"
  ]
  templates_path = (
    var.templates_path == null
    ? "${path.module}/manifest-templates"
    : pathexpand(var.templates_path)
  )
  latency-profile-generator-template               = "${path.module}/manifest-templates/latency-profile-generator.yaml.tpl"
  latency-profile-generator-podmonitoring-template = "${path.module}/manifest-templates/latency-profile-generator-podmonitoring.yaml.tpl"
  hugging_face_token_secret = (
    var.hugging_face_secret == null || var.hugging_face_secret_version == null
    ? null
    : "${var.hugging_face_secret}/versions/${var.hugging_face_secret_version}"
  )
}

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

data "google_client_config" "identity" {
  count = var.credentials_config.fleet_host != null ? 1 : 0
}


resource "kubernetes_manifest" "latency-profile-generator" {
  manifest = yamldecode(templatefile(local.latency-profile-generator-template, {
    namespace                                  = var.namespace
    artifact_registry                          = var.artifact_registry
    inference_server_framework                 = var.inference_server.name
    inference_server_service                   = var.inference_server.service.name
    inference_server_service_port              = var.inference_server.service.port
    tokenizer                                  = var.inference_server.tokenizer
    latency_profile_kubernetes_service_account = var.latency_profile_kubernetes_service_account
    prompt_dataset                             = var.prompt_dataset
    max_num_prompts                            = var.max_num_prompts
    max_output_len                             = var.max_output_len
    max_prompt_len                             = var.max_prompt_len
    benchmark_time_seconds                     = var.benchmark_time_seconds
    request_rates                              = join(",", [for number in var.request_rates : tostring(number)])
    request_timeout                            = var.request_timeout
    hugging_face_token_secret_list             = local.hugging_face_token_secret == null ? [] : [local.hugging_face_token_secret]
    k8s_hf_secret_list                         = var.k8s_hf_secret == null ? [] : [var.k8s_hf_secret]
    output_bucket                              = var.gcs_output.bucket
    output_bucket_filepath                     = var.gcs_output.filepath
    scrape_server_metrics                      = var.scrape_server_metrics
    file_prefix                                = var.file_prefix
    save_aggregated_result                     = var.save_aggregated_result
    models                                     = var.models
    stream_request                             = var.stream_request
  }))
}

resource "kubernetes_manifest" "latency-profile-generator-podmonitoring" {
  manifest = yamldecode(templatefile(local.latency-profile-generator-podmonitoring-template, {
    namespace = var.namespace
  }))
}