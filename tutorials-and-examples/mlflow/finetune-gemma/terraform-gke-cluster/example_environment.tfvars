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


##common variables
## Need to pull this variables from tf output from previous platform stage
project_id = "akvelon-gke-aieco"

## this is required for terraform to connect to GKE master and deploy workloads
create_cluster   = true # this flag will create a new standard public gke cluster in default network
cluster_name     = "dimadrogovoz-test-1"
cluster_location = "us-central1"

#######################################################
####    APPLICATIONS
#######################################################

## GKE environment variables
kubernetes_namespace = "dimadrogovoz-ai-on-gke-1"

# Creates a google service account & k8s service account & configures workload identity with appropriate permissions.
# Set to false & update the variable `workload_identity_service_account` to use an existing IAM service account.
create_service_account = false

#DISABLE IAP
create_brand = false
ray_dashboard_add_auth = false

autopilot_cluster = false

gpu_pools = [ {
    name               = "gpu-pool-l4-2"
    machine_type       = "a2-highgpu-1g"
    autoscaling        = true
    min_count          = 1
    max_count          = 3
    disk_size_gb       = 100
    disk_type          = "pd-balanced"
    enable_gcfs        = true
    accelerator_count  = 1
    accelerator_type   = "nvidia-tesla-a100"
    gpu_driver_version = "DEFAULT"
  } ]

enable_gpu = true
