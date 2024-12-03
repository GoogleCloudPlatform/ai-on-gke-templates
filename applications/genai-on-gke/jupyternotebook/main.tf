data "google_client_config" "provider" {}

data "google_container_cluster" "ai_cluster" {
  name     = "ml-cluster"
  location = "us-central1"
  project  = var.project_id
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}



provider "kubernetes" {
  host  = data.google_container_cluster.ai_cluster.endpoint
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.ai_cluster.master_auth[0].cluster_ca_certificate
  )
}

provider "kubectl" {
  host  = data.google_container_cluster.ai_cluster.endpoint
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.ai_cluster.master_auth[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}



resource "helm_release" "jupyterhub" {
  name             = "jupyterhub"
  repository       = "https://jupyterhub.github.io/helm-chart"
  chart            = "jupyterhub"
  namespace        = "jupyterhub"
  create_namespace = "true"
  cleanup_on_fail  = "true"

  values = [
    file("${path.module}/jupyter_config/config.yaml")
  ]
}
