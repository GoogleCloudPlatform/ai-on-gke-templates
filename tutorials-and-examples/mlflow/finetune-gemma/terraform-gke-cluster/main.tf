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

#######################################################
####    APPLICATIONS
#######################################################

provider "google" {
  project = var.project_id
}

provider "time" {}

data "google_client_config" "default" {}

data "google_project" "project" {
  project_id = var.project_id
}

## Enable Required GCP Project Services APIs
module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 14.5"

  project_id                  = var.project_id
  disable_services_on_destroy = false
  disable_dependent_services  = false
  activate_apis = flatten([
    "autoscaling.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "config.googleapis.com",
    "connectgateway.googleapis.com",
    "container.googleapis.com",
    "containerfilesystem.googleapis.com",
    "dns.googleapis.com",
    "gkehub.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sourcerepo.googleapis.com",
    "iap.googleapis.com"
  ])
}

module "infra" {
  source = "../../../../infrastructure"
  count  = var.create_cluster ? 1 : 0

  project_id        = var.project_id
  cluster_name      = local.cluster_name
  cluster_location  = var.cluster_location
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = false
  network_name      = "default"
  subnetwork_name   = "default"
  cpu_pools         = var.cpu_pools
  enable_gpu        = var.enable_gpu
  gpu_pools         = var.gpu_pools
  ray_addon_enabled = true
  depends_on        = [module.project-services]
}

data "google_container_cluster" "default" {
  count      = var.create_cluster ? 0 : 1
  name       = var.cluster_name
  location   = var.cluster_location
  depends_on = [module.project-services]
}

locals {
  endpoint                          = var.create_cluster ? "https://${module.infra[0].endpoint}" : "https://${data.google_container_cluster.default[0].endpoint}"
  ca_certificate                    = var.create_cluster ? base64decode(module.infra[0].ca_certificate) : base64decode(data.google_container_cluster.default[0].master_auth[0].cluster_ca_certificate)
  private_cluster                   = var.create_cluster ? var.private_cluster : data.google_container_cluster.default[0].private_cluster_config.0.enable_private_endpoint
  cluster_membership_id             = var.cluster_membership_id == "" ? local.cluster_name : var.cluster_membership_id
  enable_autopilot                  = var.create_cluster ? var.autopilot_cluster : data.google_container_cluster.default[0].enable_autopilot
  enable_tpu                        = var.create_cluster ? var.enable_tpu : data.google_container_cluster.default[0].enable_tpu
  host                              = local.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : local.endpoint
  kubernetes_namespace              = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.kubernetes_namespace}" : var.kubernetes_namespace
  workload_identity_service_account = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.workload_identity_service_account}" : var.workload_identity_service_account
  cluster_name                      = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.cluster_name}" : var.cluster_name
  #ray_cluster_default_uri           = "https://console.cloud.google.com/kubernetes/service/${var.cluster_location}/${local.cluster_name}/${local.kubernetes_namespace}/${var.ray_cluster_name}-kuberay-head-svc/overview?project=${var.project_id}"
}

# provider "kubernetes" {
#   alias                  = "ray"
#   host                   = local.host
#   token                  = data.google_client_config.default.access_token
#   cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
#   dynamic "exec" {
#     for_each = local.private_cluster ? [1] : []
#     content {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "gke-gcloud-auth-plugin"
#     }
#   }
# }

# provider "helm" {
#   alias = "ray"
#   kubernetes {
#     host                   = local.host
#     token                  = data.google_client_config.default.access_token
#     cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
#     dynamic "exec" {
#       for_each = local.private_cluster ? [1] : []
#       content {
#         api_version = "client.authentication.k8s.io/v1beta1"
#         command     = "gke-gcloud-auth-plugin"
#       }
#     }
#   }
# }

# module "namespace" {
#   source           = "../../modules/kubernetes-namespace"
#   providers        = { helm = helm.ray }
#   create_namespace = true
#   namespace        = local.kubernetes_namespace
# }

# module "kuberay-workload-identity" {
#   providers                       = { kubernetes = kubernetes.ray }
#   source                          = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
#   version                         = "30.0.0" # Pinning to a previous version as current version (30.1.0) showed inconsitent behaviour with workload identity service accounts
#   use_existing_gcp_sa             = !var.create_service_account
#   name                            = local.workload_identity_service_account
#   namespace                       = local.kubernetes_namespace
#   project_id                      = var.project_id
#   roles                           = ["roles/cloudsql.client", "roles/monitoring.viewer"]
#   automount_service_account_token = true
#   depends_on                      = [module.namespace]
# }

# module "kuberay-monitoring" {
#   count                           = var.create_ray_cluster ? 1 : 0
#   source                          = "../../modules/kuberay-monitoring"
#   providers                       = { helm = helm.ray, kubernetes = kubernetes.ray }
#   project_id                      = var.project_id
#   autopilot_cluster               = var.autopilot_cluster
#   namespace                       = local.kubernetes_namespace
#   create_namespace                = true
#   enable_grafana_on_ray_dashboard = var.enable_grafana_on_ray_dashboard
#   k8s_service_account             = local.workload_identity_service_account
#   depends_on                      = [module.kuberay-workload-identity]
# }

# module "gcs" {
#   source      = "../../modules/gcs"
#   count       = var.create_gcs_bucket ? 1 : 0
#   project_id  = var.project_id
#   bucket_name = var.gcs_bucket
# }

# module "kuberay-cluster" {
#   count                     = var.create_ray_cluster == true ? 1 : 0
#   source                    = "../../modules/kuberay-cluster"
#   providers                 = { helm = helm.ray, kubernetes = kubernetes.ray }
#   name                      = var.ray_cluster_name
#   namespace                 = local.kubernetes_namespace
#   project_id                = var.project_id
#   enable_tpu                = local.enable_tpu
#   enable_gpu                = var.enable_gpu
#   gcs_bucket                = var.gcs_bucket
#   autopilot_cluster         = local.enable_autopilot
#   google_service_account    = local.workload_identity_service_account
#   grafana_host              = var.enable_grafana_on_ray_dashboard ? module.kuberay-monitoring[0].grafana_uri : ""
#   network_policy_allow_cidr = var.kuberay_network_policy_allow_cidr
#   disable_network_policy    = var.disable_ray_cluster_network_policy
#   additional_labels         = var.additional_labels

#   # IAP Auth parameters
#   add_auth                 = var.ray_dashboard_add_auth
#   create_brand             = var.create_brand
#   support_email            = var.support_email
#   client_id                = var.ray_dashboard_client_id
#   client_secret            = var.ray_dashboard_client_secret
#   k8s_ingress_name         = var.ray_dashboard_k8s_ingress_name
#   k8s_iap_secret_name      = var.ray_dashboard_k8s_iap_secret_name
#   k8s_managed_cert_name    = var.ray_dashboard_k8s_managed_cert_name
#   k8s_backend_config_name  = var.ray_dashboard_k8s_backend_config_name
#   k8s_backend_service_port = var.ray_dashboard_k8s_backend_service_port
#   domain                   = var.ray_dashboard_domain
#   members_allowlist        = var.ray_dashboard_members_allowlist != "" ? split(",", var.ray_dashboard_members_allowlist) : []
#   depends_on               = [module.gcs, module.kuberay-workload-identity]
# }


# # Assign resource quotas to Ray namespace to ensure that they don't overutilize resources
# resource "kubernetes_resource_quota" "ray_namespace_resource_quota" {
#   provider = kubernetes.ray
#   count    = var.disable_resource_quotas ? 0 : 1
#   metadata {
#     name      = "ray-resource-quota"
#     namespace = local.kubernetes_namespace
#   }

#   spec {
#     hard = var.resource_quotas
#   }

#   depends_on = [module.namespace]
# }
