data "google_container_cluster" "nim-llm" {
  name     = var.cluster-name
  location = var.cluster-location
}

data "google_client_config" "current" {

}

resource "kubernetes_namespace" "nim" {
  metadata {
    name = var.kubernetes-namespace
  }
}

resource "kubernetes_secret" "ngc-secret" {
  metadata {
    name      = "ngc-secret"
    namespace = kubernetes_namespace.nim.metadata.0.name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" = {
        "nvcr.io" = {
          "username" = "$oauthtoken"
          "password" = var.ngc-api-key
          "auth"     = base64encode("$oauthtoken:${var.ngc-api-key}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_secret" "ngc-api" {
  metadata {
    name      = "ngc-api"
    namespace = kubernetes_namespace.nim.metadata.0.name
  }

  type = "Opaque"

  data = {
    NGC_API_KEY = var.ngc-api-key
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_storage_class" "name" {
  metadata {
    name = "hyperdisk-ml"
  }

  parameters = {
    type = "hyperdisk-ml"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  allow_volume_expansion = false
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
}

resource "kubernetes_persistent_volume_claim" "name" {
  metadata {
    generate_name = "pvc-nim-"
    namespace     = kubernetes_namespace.nim.metadata.0.name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.name.metadata.0.name
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
  wait_until_bound = false
}

resource "helm_release" "nim-release" {
  name                = "nim"
  namespace           = kubernetes_namespace.nim.metadata.0.name
  chart               = "https://helm.ngc.nvidia.com/nim/charts/nim-llm-${var.chart-version}.tgz"
  repository_username = "$oauthtoken"
  repository_password = var.ngc-api-key

  set {
    name  = "image.repository"
    value = "nvcr.io/nim/${var.image-name}"
  }

  set {
    name  = "image.tag"
    value = var.image-tag
  }

  set {
    name  = "model.name"
    value = var.image-name
  }

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "resources.limits.nvidia\\.com/gpu"
    value = var.gpu-limits
  }

  set {
    name  = "persistence.enabled"
    value = true
  }

  set {
    name  = "persistence.existingClaim"
    value = kubernetes_persistent_volume_claim.name.metadata.0.name
  }

  depends_on = [kubernetes_namespace.nim]
}
