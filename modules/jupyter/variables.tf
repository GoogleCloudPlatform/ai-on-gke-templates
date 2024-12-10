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

variable "namespace" {
  type        = string
  description = "Kubernetes namespace where resources are deployed"
}

variable "notebook_image" {
  type        = string
  description = "Jupyter notebook image name"
  default     = "jupyter/tensorflow-notebook"
}

variable "notebook_image_tag" {
  type        = string
  description = "Jupyter notebook image tag"
  default     = "python-3.11"
}

variable "members_allowlist" {
  type    = list(string)
  default = []
}

variable "add_auth" {
  type        = bool
  description = "Enable iap authentication on jupyterhub"
  default     = true
}

variable "gcs_bucket" {
  type        = string
  description = "GCS bucket to mount on the notebook via GCSFuse and CSI"
}

variable "additional_labels" {
  // string is used instead of map(string) since blueprint metadata does not support maps.
  type        = string
  description = "Additional labels to add to Kubernetes resources."
  default     = "created-by=ai-on-gke,ai.gke.io=jupyter"
}

variable "workload_identity_service_account" {
  type        = string
  description = "workload identity service account"
}

variable "gcp_service_account_iam_roles" {
  type        = list(string)
  description = "Service Account Project IAM binding roles"
  default     = []
}

# TODO review all permissions
variable "predefined_iam_roles" {
  description = "Predefined list of IAM roles to assign"
  type        = list(string)
  default     = ["roles/compute.networkViewer", "roles/viewer", "roles/cloudsql.client", "roles/artifactregistry.reader", "roles/storage.admin", "roles/iam.serviceAccountAdmin", "roles/compute.loadBalancerServiceUser", "roles/iam.serviceAccountTokenCreator"]
}

variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "k8s_ingress_name" {
  type    = string
  default = "jupyter-ingress"
}

variable "k8s_managed_cert_name" {
  type        = string
  description = "Name for frontend managed certificate"
  default     = "jupyter-managed-cert"
}

variable "k8s_iap_secret_name" {
  type    = string
  default = "jupyter-secret"
}

variable "k8s_backend_config_name" {
  type        = string
  description = "Name of the Backend Config on GCP"
  default     = "jupyter-iap-config"
}

variable "k8s_backend_service_name" {
  type        = string
  description = "Name of the Backend Service on GCP, this is defined by Jupyter hub"
  default     = "proxy-public"
}

variable "k8s_backend_service_port" {
  type        = number
  description = "Name of the Backend Service on GCP"
  default     = 80
}

variable "create_brand" {
  type        = bool
  description = "Create Brand OAuth Screen"
}

variable "domain" {
  type        = string
  description = "Provide domain for ingress resource and ssl certificate."
  default     = ""
}

variable "support_email" {
  type        = string
  description = "Email for users to contact with questions about their consent"
}

variable "client_id" {
  type        = string
  description = "Client ID used for enabling IAP"
  default     = ""
}

variable "client_secret" {
  type        = string
  description = "Client secret used for enabling IAP"
  default     = ""
  sensitive   = false
}

variable "ephemeral_storage" {
  type        = string
  description = "The amount of ephemeral storage for each user"
  default     = "20Gi"
}

variable "autopilot_cluster" {
  type = bool
}

variable "db_region" {
  type        = string
  description = "Cloud SQL instance region"
  default     = ""
}

variable "db_secret_name" {
  type        = string
  description = "CloudSQL user credentials"
  default     = "dummy_value"
}

variable "cloudsql_instance_name" {
  type        = string
  description = "Cloud SQL instance name"
  default     = ""
}

