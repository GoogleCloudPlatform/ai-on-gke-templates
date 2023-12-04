# Copyright 2023 Google LLC
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

variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "region" {
  type        = string
  description = "GCP project region or zone"
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
  default     = "ml-cluster"
}

variable "cluster_labels" {
  type        = map
  description = "GKE cluster labels"
  default     =  {
    created-by = "ai-on-gke"
  }
}

variable "enable_autopilot" {
  type        = bool
  description = "Set to true to enable GKE Autopilot clusters"
  default     = false
}

variable "enable_tpu" {
  type        = bool
  description = "Set to true to create TPU node pool"
  default     = false
}

variable "gpu_pool_node_locations" {
  type        = list
  description = "Specify the gpu-pool node zone locations, they will be derived from the region and gpu type if omitted."
  default     = null
}

variable "gpu_pool_machine_cfg" {
  type        = string
  description = "Use a gpu/cpu combo, see locals.tf for details."
  default     = "nvidia_l4_x1"
}
