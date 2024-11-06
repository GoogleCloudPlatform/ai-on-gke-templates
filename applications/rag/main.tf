# Copyright 2024 Google LLC
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

provider "google" {
  project = var.project_id
}
provider "google-beta" {
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
    "dlp.googleapis.com",
    "dns.googleapis.com",
    "gkehub.googleapis.com",
    "iamcredentials.googleapis.com",
    "language.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sourcerepo.googleapis.com",
    "sqladmin.googleapis.com",
    "iap.googleapis.com"
  ])
}

module "infra" {
  source = "../../infrastructure"
  count  = var.create_cluster ? 1 : 0

  project_id        = var.project_id
  cluster_name      = local.cluster_name
  cluster_location  = var.cluster_location
  region            = local.cluster_location_region
  autopilot_cluster = var.autopilot_cluster
  private_cluster   = var.private_cluster
  create_network    = var.create_network
  network_name      = local.network_name
  subnetwork_name   = local.network_name
  subnetwork_cidr   = var.subnetwork_cidr
  subnetwork_region = local.cluster_location_region
  cpu_pools         = var.cpu_pools
  enable_gpu        = true
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
  endpoint              = var.create_cluster ? "https://${module.infra[0].endpoint}" : "https://${data.google_container_cluster.default[0].endpoint}"
  ca_certificate        = var.create_cluster ? base64decode(module.infra[0].ca_certificate) : base64decode(data.google_container_cluster.default[0].master_auth[0].cluster_ca_certificate)
  private_cluster       = var.create_cluster ? var.private_cluster : data.google_container_cluster.default[0].private_cluster_config.0.enable_private_endpoint
  cluster_membership_id = var.cluster_membership_id == "" ? var.cluster_name : var.cluster_membership_id
  enable_autopilot      = var.create_cluster ? var.autopilot_cluster : data.google_container_cluster.default[0].enable_autopilot
  host                  = local.private_cluster ? "https://connectgateway.googleapis.com/v1/projects/${data.google_project.project.number}/locations/${var.cluster_location}/gkeMemberships/${local.cluster_membership_id}" : local.endpoint
}

## Generated names for marketplace deployment
locals {
  cluster_name            = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.cluster_name}" : var.cluster_name
  kubernetes_namespace    = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.kubernetes_namespace}" : var.kubernetes_namespace
  network_name            = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.network_name}" : var.network_name
  ray_service_account     = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.ray_service_account}" : var.ray_service_account
  jupyter_service_account = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.jupyter_service_account}" : var.jupyter_service_account
  rag_service_account     = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.rag_service_account}" : var.rag_service_account
  frontend_default_uri    = "https://console.cloud.google.com/kubernetes/service/${var.cluster_location}/${local.cluster_name}/${local.kubernetes_namespace}/rag-frontend/overview?project=${var.project_id}"
  jupyterhub_default_uri  = "https://console.cloud.google.com/kubernetes/service/${var.cluster_location}/${local.cluster_name}/${local.kubernetes_namespace}/proxy-public/overview?project=${var.project_id}"
  ## if cloudsql_instance_region not specified, then default to cluster_location region
  cluster_location_region  = (length(split("-", var.cluster_location)) == 2 ? var.cluster_location : join("-", slice(split("-", var.cluster_location), 0, 2)))
  cloudsql_instance_region = var.cloudsql_instance_region != "" ? var.cloudsql_instance_region : local.cluster_location_region
  cloudsql_instance        = var.goog_cm_deployment_name != "" ? "${var.goog_cm_deployment_name}-${var.cloudsql_instance}" : var.cloudsql_instance
}


provider "kubernetes" {
  alias                  = "rag"
  host                   = local.host
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
  dynamic "exec" {
    for_each = local.private_cluster ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

provider "helm" {
  alias = "rag"
  kubernetes {
    host                   = local.host
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = local.private_cluster ? "" : local.ca_certificate
    dynamic "exec" {
      for_each = local.private_cluster ? [1] : []
      content {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "gke-gcloud-auth-plugin"
      }
    }
  }
}

module "namespace" {
  source           = "../../modules/kubernetes-namespace"
  providers        = { helm = helm.rag }
  create_namespace = true
  namespace        = local.kubernetes_namespace
}

module "gcs" {
  source      = "../../modules/gcs"
  count       = var.create_gcs_bucket ? 1 : 0
  project_id  = var.project_id
  bucket_name = var.gcs_bucket
}

module "cloudsql" {
  source        = "../../modules/cloudsql"
  providers     = { kubernetes = kubernetes.rag }
  project_id    = var.project_id
  instance_name = local.cloudsql_instance
  namespace     = local.kubernetes_namespace
  region        = local.cloudsql_instance_region
  network_name  = local.network_name
  depends_on    = [module.namespace]
}

module "jupyterhub" {
  source            = "../../modules/jupyter"
  providers         = { helm = helm.rag, kubernetes = kubernetes.rag }
  namespace         = local.kubernetes_namespace
  project_id        = var.project_id
  gcs_bucket        = var.gcs_bucket
  add_auth          = var.jupyter_add_auth
  additional_labels = var.additional_labels

  autopilot_cluster                 = local.enable_autopilot
  workload_identity_service_account = local.jupyter_service_account

  notebook_image     = "us-central1-docker.pkg.dev/ai-on-gke/rag-on-gke/jupyter-notebook-image"
  notebook_image_tag = "v1.1-rag"

  db_secret_name         = module.cloudsql.db_secret_name
  cloudsql_instance_name = local.cloudsql_instance
  db_region              = local.cloudsql_instance_region

  # IAP Auth parameters
  create_brand             = var.create_brand
  support_email            = var.support_email
  client_id                = var.jupyter_client_id
  client_secret            = var.jupyter_client_secret
  k8s_ingress_name         = var.jupyter_k8s_ingress_name
  k8s_iap_secret_name      = var.jupyter_k8s_iap_secret_name
  k8s_managed_cert_name    = var.jupyter_k8s_managed_cert_name
  k8s_backend_config_name  = var.jupyter_k8s_backend_config_name
  k8s_backend_service_name = var.jupyter_k8s_backend_service_name
  k8s_backend_service_port = var.jupyter_k8s_backend_service_port
  domain                   = var.jupyter_domain
  members_allowlist        = var.jupyter_members_allowlist != "" ? split(",", var.jupyter_members_allowlist) : []

  depends_on = [module.namespace, module.gcs]
}

module "kuberay-workload-identity" {
  providers                       = { kubernetes = kubernetes.rag }
  source                          = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version                         = "30.0.0" # Pinning to a previous version as current version (30.1.0) showed inconsitent behaviour with workload identity service accounts
  use_existing_gcp_sa             = !var.create_ray_service_account
  name                            = local.ray_service_account
  namespace                       = local.kubernetes_namespace
  project_id                      = var.project_id
  roles                           = ["roles/cloudsql.client", "roles/monitoring.viewer"]
  automount_service_account_token = true
  depends_on                      = [module.namespace]
}

module "kuberay-monitoring" {
  source                          = "../../modules/kuberay-monitoring"
  providers                       = { helm = helm.rag, kubernetes = kubernetes.rag }
  project_id                      = var.project_id
  autopilot_cluster               = local.enable_autopilot
  namespace                       = local.kubernetes_namespace
  create_namespace                = true
  enable_grafana_on_ray_dashboard = var.enable_grafana_on_ray_dashboard
  k8s_service_account             = local.ray_service_account
  depends_on                      = [module.namespace, module.kuberay-workload-identity]
}

module "kuberay-cluster" {
  source                 = "../../modules/kuberay-cluster"
  providers              = { helm = helm.rag, kubernetes = kubernetes.rag }
  project_id             = var.project_id
  namespace              = local.kubernetes_namespace
  enable_gpu             = true
  gcs_bucket             = var.gcs_bucket
  autopilot_cluster      = local.enable_autopilot
  cloudsql_instance_name = local.cloudsql_instance
  db_region              = local.cloudsql_instance_region
  google_service_account = local.ray_service_account
  disable_network_policy = var.disable_ray_cluster_network_policy
  use_custom_image       = true
  additional_labels      = var.additional_labels

  # Implicit dependency
  db_secret_name = module.cloudsql.db_secret_name
  grafana_host   = module.kuberay-monitoring.grafana_uri

  # IAP Auth parameters
  add_auth                 = var.ray_dashboard_add_auth
  create_brand             = var.create_brand
  support_email            = var.support_email
  client_id                = var.ray_dashboard_client_id
  client_secret            = var.ray_dashboard_client_secret
  k8s_ingress_name         = var.ray_dashboard_k8s_ingress_name
  k8s_iap_secret_name      = var.ray_dashboard_k8s_iap_secret_name
  k8s_managed_cert_name    = var.ray_dashboard_k8s_managed_cert_name
  k8s_backend_config_name  = var.ray_dashboard_k8s_backend_config_name
  k8s_backend_service_port = var.ray_dashboard_k8s_backend_service_port
  domain                   = var.ray_dashboard_domain
  members_allowlist        = var.ray_dashboard_members_allowlist != "" ? split(",", var.ray_dashboard_members_allowlist) : []
  depends_on               = [module.gcs, module.kuberay-workload-identity]
}

module "inference-server" {
  source            = "../../modules/inference-service"
  providers         = { kubernetes = kubernetes.rag }
  namespace         = local.kubernetes_namespace
  additional_labels = var.additional_labels
  autopilot_cluster = local.enable_autopilot
  depends_on        = [module.namespace]
}

module "frontend" {
  source                        = "./frontend"
  providers                     = { helm = helm.rag, kubernetes = kubernetes.rag }
  project_id                    = var.project_id
  region                        = var.cluster_location
  create_service_account        = var.create_rag_service_account
  google_service_account        = local.rag_service_account
  namespace                     = local.kubernetes_namespace
  additional_labels             = var.additional_labels
  inference_service_endpoint    = module.inference-server.inference_service_endpoint
  cloudsql_instance             = module.cloudsql.instance
  cloudsql_instance_region      = local.cloudsql_instance_region
  db_secret_name                = module.cloudsql.db_secret_name
  dataset_embeddings_table_name = var.dataset_embeddings_table_name

  # IAP Auth parameters
  add_auth                 = var.frontend_add_auth
  create_brand             = var.create_brand
  support_email            = var.support_email
  client_id                = var.frontend_client_id
  client_secret            = var.frontend_client_secret
  k8s_ingress_name         = var.frontend_k8s_ingress_name
  k8s_managed_cert_name    = var.frontend_k8s_managed_cert_name
  k8s_iap_secret_name      = var.frontend_k8s_iap_secret_name
  k8s_backend_config_name  = var.frontend_k8s_backend_config_name
  k8s_backend_service_name = var.frontend_k8s_backend_service_name
  k8s_backend_service_port = var.frontend_k8s_backend_service_port
  domain                   = var.frontend_domain
  members_allowlist        = var.frontend_members_allowlist != "" ? split(",", var.frontend_members_allowlist) : []
  depends_on               = [module.namespace]
}

resource "helm_release" "gmp-apps" {
  name      = "gmp-apps"
  provider  = helm.rag
  chart     = "../../charts/gmp-engine/"
  namespace = local.kubernetes_namespace
  # Timeout is increased to guarantee sufficient scale-up time for Autopilot nodes.
  timeout    = 1200
  depends_on = [module.inference-server, module.frontend]
  values = [
    "${file("${path.module}/podmonitoring.yaml")}"
  ]
}

