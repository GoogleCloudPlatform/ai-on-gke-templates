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
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  instance_connection_name = format("%s:%s:%s", var.project_id, var.cloudsql_instance_region, var.cloudsql_instance)
  additional_labels = tomap({
    for item in split(",", var.additional_labels) :
    split("=", item)[0] => split("=", item)[1]
  })
}

resource "random_string" "application_secret_key" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

# IAP Section: Creates the GKE components
module "iap_auth" {
  count  = var.add_auth ? 1 : 0
  source = "../../../modules/iap"

  project_id               = var.project_id
  namespace                = var.namespace
  support_email            = var.support_email
  app_name                 = "frontend"
  create_brand             = var.create_brand
  k8s_ingress_name         = var.k8s_ingress_name
  k8s_managed_cert_name    = var.k8s_managed_cert_name
  k8s_iap_secret_name      = var.k8s_iap_secret_name
  k8s_backend_config_name  = var.k8s_backend_config_name
  k8s_backend_service_name = var.k8s_backend_service_name
  k8s_backend_service_port = var.k8s_backend_service_port
  client_id                = var.client_id
  client_secret            = var.client_secret
  domain                   = var.domain
  members_allowlist        = var.members_allowlist
  depends_on = [
    kubernetes_service.rag_frontend_service, kubernetes_deployment.rag_frontend_deployment
  ]
}

module "frontend-workload-identity" {
  source              = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version             = "30.0.0" # Pinning to a previous version as current version (30.1.0) showed inconsitent behaviour with workload identity service accounts
  use_existing_gcp_sa = !var.create_service_account
  name                = var.google_service_account
  namespace           = var.namespace
  project_id          = var.project_id
  roles               = ["roles/cloudsql.client", "roles/dlp.admin"]
}

resource "kubernetes_service" "rag_frontend_service" {
  metadata {
    name      = "rag-frontend"
    namespace = var.namespace
  }
  spec {
    selector = {
      app = "rag-frontend"
    }
    session_affinity = var.add_auth ? "None" : "ClientIP"
    port {
      port        = 8080
      target_port = 8080
    }

    type = var.add_auth ? "NodePort" : "ClusterIP"
  }
  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
    ]
  }
}

resource "kubernetes_deployment" "rag_frontend_deployment" {
  metadata {
    name      = "rag-frontend"
    namespace = var.namespace
    labels = merge({
      app = "rag-frontend"
    }, local.additional_labels)
  }

  spec {
    replicas = 3
    selector {
      match_labels = merge({
        app = "rag-frontend"
      }, local.additional_labels)
    }

    template {
      metadata {
        labels = merge({
          app = "rag-frontend"
        }, local.additional_labels)
      }

      spec {
        service_account_name = var.google_service_account
        container {
          # image = "us-central1-docker.pkg.dev/ai-on-gke/rag-on-gke/frontend@sha256:d65b538742ee29826ee629cfe05c0008e7c09ce5357ddc08ea2eaf3fd6cefe4b"
          image = "us-docker.pkg.dev/globant-gke-ai-resources/gke-ai-text-to-text/gke-rag-frontend@sha256:e6960ded132211f02d7442177bd6454ccd65b29768e62ebb47f14c17a30a46f2"

          name = "rag-frontend"

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "secret-volume"
            mount_path = "/etc/secret-volume"
            read_only  = true
          }

          env {
            name = "GCP_PROJECT_ID"
            #value = "projects/${var.project_id}"
            value = var.project_id
          }

          env {
            name  = "CLOUDSQL_INSTANCE_REGION"
            value = var.region
          }

          env {
            name  = "CLOUDSQL_INSTANCE"
            value = var.cloudsql_instance
          }

          env {
            name  = "INSTANCE_CONNECTION_NAME"
            value = local.instance_connection_name
          }

          env {
            name  = "INFERENCE_ENDPOINT"
            value = var.inference_service_endpoint
          }

          env {
            name  = "EMBEDDINGS_TABLE_NAME"
            value = var.dataset_embeddings_table_name
          }

          env {
            name  = "APPLICATION_SECRET_KEY"
            value = random_string.application_secret_key.result
          }

          resources {
            limits = {
              cpu               = "3"
              memory            = "8Gi"
              ephemeral-storage = "5Gi"
            }
            requests = {
              cpu               = "3"
              memory            = "8Gi"
              ephemeral-storage = "5Gi"
            }
          }
        }

        volume {
          secret {
            secret_name = var.db_secret_name
          }
          name = "secret-volume"
        }

        container {
          image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0"
          name  = "cloud-sql-proxy"

          args = [
            "--structured-logs",
            local.instance_connection_name,
          ]

          security_context {
            run_as_non_root = true
          }

          resources {
            limits = {
              cpu    = "1"
              memory = "2Gi"
            }
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
          }
        }
      }
    }
  }
}
