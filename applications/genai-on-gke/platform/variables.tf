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
  default     = ""
}

variable "region" {
  type        = string
  description = "GCP project region or zone"
  default     = "us-central1"
}
##handle api
variable "services" {
  description = "Service APIs to enable."
  type        = list(string)
  default     = []
}

variable "master_ipv4_cidr_block" {
  type    = string
  default = ""
}


variable "service_config" {
  description = "Configure service API activation."
  type = object({
    disable_on_destroy         = bool
    disable_dependent_services = bool
  })
  default = {
    disable_on_destroy         = false
    disable_dependent_services = false
  }
}

## network variables
variable "create_network" {
  type = bool
}

variable "network_name" {
  type = string
}

variable "subnetwork_name" {
  type = string
}

variable "subnetwork_cidr" {
  type = string
}

variable "subnetwork_region" {
  type = string
}

variable "subnetwork_private_access" {
  type = string
}

variable "subnetwork_description" {
  type = string
}

variable "network_secondary_ranges" {
  type = map(list(object({ range_name = string, ip_cidr_range = string })))
}

## GKE variables
variable "create_cluster" {
  type = bool
}

variable "private_cluster" {
  type    = bool
  default = true
}

variable "autopilot_cluster" {
  type = bool
}

variable "cluster_regional" {
  type = bool
}

variable "cluster_name" {
  type = string
}

variable "cluster_labels" {
  type        = map(any)
  description = "GKE cluster labels"
  default = {
    "cloud.google.com/gke-profile" = "ai-on-gke"
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.28.5-gke.1217000"
}

variable "cluster_region" {
  type = string
}

variable "cluster_zones" {
  type = list(string)
}
variable "ip_range_pods" {
  type = string
}
variable "ip_range_services" {
  type = string
}
variable "monitoring_enable_managed_prometheus" {
  type    = bool
  default = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "all_node_pools_oauth_scopes" {
  type = list(string)
}
variable "all_node_pools_labels" {
  type = map(string)
}
variable "all_node_pools_metadata" {
  type = map(string)
}
variable "all_node_pools_tags" {
  type = list(string)
}

variable "enable_tpu" {
  type        = bool
  description = "Set to true to create TPU node pool"
  default     = false
}
variable "enable_gpu" {
  type        = bool
  description = "Set to true to create TPU node pool"
  default     = true
}

variable "cpu_pools" {
  type = list(map(any))
}

variable "gpu_pools" {
  type = list(map(any))
}

variable "tpu_pools" {
  type = list(map(any))
}
