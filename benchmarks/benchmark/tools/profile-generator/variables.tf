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

variable "credentials_config" {
  description = "Configure how Terraform authenticates to the cluster."
  type = object({
    fleet_host = optional(string)
    kubeconfig = optional(object({
      context = optional(string)
      path    = optional(string, "~/.kube/config")
    }))
  })
  nullable = false
  validation {
    condition = (
      (var.credentials_config.fleet_host != null) !=
      (var.credentials_config.kubeconfig != null)
    )
    error_message = "Exactly one of fleet host or kubeconfig must be set."
  }
}

variable "namespace" {
  description = "Namespace used for model and benchmarking deployments."
  type        = string
  nullable    = false
  default     = "default"
}

variable "project_id" {
  description = "Project id of existing or created project."
  type        = string
  nullable    = false
}

variable "templates_path" {
  description = "Path where manifest templates will be read from. Set to null to use the default manifests"
  type        = string
  default     = null
}

variable "artifact_registry" {
  description = "Artifact registry for storing Latency Profile Generator container."
  type        = string
  default     = null
}

variable "build_latency_profile_generator_image" {
  description = "Whether latency profile generator image will be built or not"
  type        = bool
  default     = true
}

variable "prompt_dataset" {
  description = "Prompt dataset URL"
  type        = string
  nullable    = false
  default     = "sharegpt"
  validation {
    condition     = contains(["sharegpt"], var.prompt_dataset)
    error_message = "prompt_dataset must be one of the following: 'sharegpt'"
  }
}

variable "max_num_prompts" {
  description = "Benchmark server configuration for max number of prompts."
  type        = number
  default     = 1000
  validation {
    condition     = var.max_num_prompts > 0
    error_message = "The max_num_prompts value must be greater than 0."
  }
}

variable "max_output_len" {
  description = "Benchmark server configuration for max output length."
  type        = number
  default     = 256
  validation {
    condition     = var.max_output_len > 4
    error_message = "The max_output_len value must be greater than 4. TGI framework throws an error for too short of sequences."
  }
}

variable "max_prompt_len" {
  description = "Benchmark server configuration for max prompt length."
  type        = number
  default     = 256
  validation {
    condition     = var.max_prompt_len > 4
    error_message = "The max_prompt_len value must be greater than 4. TGI framework throws an error for too short of sequences."
  }
}

variable "request_rates" {
  description = ""
  type        = list(number)
  default     = [1, 2]
  nullable    = false
}

variable "request_timeout" {
  description = "Timeout per mock request in seconds"
  type        = number
  default     = 10800
  nullable    = false
}

variable "output_bucket" {
  description = "Bucket name for storing results"
  type        = string
  nullable    = true
  default     = ""
}

variable "output_bucket_filepath" {
  description = "Where in bucket to store json results, will upload to root of bucket if not specified"
  type        = string
  nullable    = true
  default     = ""
}

variable "latency_profile_kubernetes_service_account" {
  description = "Kubernetes Service Account to be used for the latency profile generator tool"
  type        = string
  default     = "sample-runner-ksa"
}

// TODO: add validation to make k8s_hf_secret & hugging_face_secret mutually exclusive once terraform is updated with: https://discuss.hashicorp.com/t/experiment-feedback-input-variable-validation-can-cross-reference-other-objects/66644
variable "k8s_hf_secret" {
  description = "Name of secret for huggingface token; stored in k8s "
  type        = string
  nullable    = true
  default     = null
}

variable "hugging_face_secret" {
  description = "name of the kubectl huggingface secret token; stored in Secret Manager. Security considerations: https://kubernetes.io/docs/concepts/security/secrets-good-practices/"
  type        = string
  nullable    = true
  default     = null
}

variable "hugging_face_secret_version" {
  description = "Secret version in Secret Manager"
  type        = string
  nullable    = true
  default     = null
}

variable "targets" {
  description = "Model server(s) targeted for benchmarking, use 'manual' for already installed model servers"
  type = object({
    manual = object({
      name         = string
      service_name = string
      service_port = number
      tokenizer    = string
    })
  })
}

variable "models" {
  description = "A list of comma separated models to benchmark."
  type        = string
  nullable    = false
  default     = "tiiuae/falcon-7b"
}

variable "scrape_server_metrics" {
  description = "Whether to scrape server metrics."
  type        = bool
  default     = false
}

variable "benchmark_time_seconds" {
  description = "The amount of time (in seconds) the benchmark should be run at each request rate"
  type        = number
  default     = 120
  nullable    = false
}

variable "file_prefix" {
  description = "A prefix to the saved json file, useful to add additional context to the benchmark."
  type        = string
  nullable    = false
  default     = "benchmark"
}

variable "save_aggregated_result" {
  description = "Whether to save aggregated result, useful when benchmarking multiple models."
  type        = bool
  default     = false
}

variable "stream_request" {
  description = "Whether to stream the request. Needed for TTFT metric"
  type        = bool
  default     = false
}