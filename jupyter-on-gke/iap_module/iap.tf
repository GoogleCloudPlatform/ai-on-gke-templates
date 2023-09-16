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

# provider "kubernetes" {
#   config_path = pathexpand("~/.kube/config")
# }

# provider "kubectl" {
#   config_path = pathexpand("~/.kube/config")
# }

# provider "google" {
#   config_path = pathexpand("~/.kube/config")
#   project = var.project_id
#   region = var.location
# }

# provider "google-beta" {
#   config_path = pathexpand("~/.kube/config")
#   project = var.project_id
#   region = var.location
# }

data "local_file" "backend_config_yaml" {
  filename = "${path.module}/deployments/backend-config.yaml"
}

data "local_file" "managed_cert_yaml" {
  filename = "${path.module}/deployments/managed-cert.yaml"
}

data "local_file" "static_ingress_yaml" {
  filename = "${path.module}/deployments/static-ingress.yaml"
}

data "google_compute_backend_service" "jupyter-ingress" {
  name = var.service_name
  project = var.project_id

  depends_on = [ kubectl_manifest.backend_config ]
}

# Reserve IP Address
resource "google_compute_global_address" "default" {
  provider     = google-beta
  project      = var.project_id
  name         = "jupyter-address"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "kubectl_manifest" "backend_config" {
  override_namespace = var.namespace
  yaml_body          = templatefile("${path.module}/deployments/backend-config.yaml", {})
  depends_on = [ kubectl_manifest.static_ingress ]
}

resource "kubectl_manifest" "managed_cert" {
  override_namespace = var.namespace
  yaml_body          = templatefile("${path.module}/deployments/managed-cert.yaml", {
    ip_addr = "${google_compute_global_address.default.address}.nip.io"
  })
  depends_on = [ google_compute_global_address.default ]
}

resource "kubectl_manifest" "static_ingress" {
  override_namespace = var.namespace
  yaml_body          = templatefile("${path.module}/deployments/static-ingress.yaml", {
    static_addr_name = "${google_compute_global_address.default.name}"
  })
  depends_on = [ google_compute_global_address.default, kubectl_manifest.managed_cert ]
}

resource "kubernetes_secret" "my-secret" {
  metadata {
    name = "my-secret"
    namespace = var.namespace
  }

  # Omitting type defaults to `Opaque` which is the equivalent of `generic` 
  data = {
    "client_id" = var.client_id
    "client_secret" = var.client_secret
  }
}