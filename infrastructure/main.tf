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
####    PLATFORM
#######################################################

## GPU locations where L4 & T4 are supported.
locals {
  gpu_l4_t4_location = {
    asia-east1      = "asia-east1-a,asia-east1-c"
    asia-northeast1 = "asia-northeast1-a,asia-northeast1-c"
    asia-northeast3 = "asia-northeast3-b"
    asia-south1     = "asia-south1-a,asia-south1-b"
    asia-southeast1 = "asia-southeast1-a,asia-southeast1-b,asia-southeast1-c"
    europe-west1    = "europe-west1-b,europe-west1-c"
    europe-west2    = "europe-west2-a,europe-west2-b"
    europe-west3    = "europe-west3-b"
    europe-west4    = "europe-west4-a,europe-west4-b,europe-west4-c"
    us-central1     = "us-central1-a,us-central1-b,us-central1-c"
    us-east1        = "us-east1-c,us-east1-d"
    us-east4        = "us-east4-a,us-east4-c"
    us-west1        = "us-west1-a,us-west1-b"
    us-west4        = "us-west4-a"
  }
}

data "google_compute_network" "existing-network" {
  count   = var.create_network ? 0 : 1
  name    = var.network_name
  project = var.project_id
}

data "google_compute_subnetwork" "subnetwork" {
  count   = var.create_network ? 0 : 1
  name    = var.subnetwork_name
  region  = var.subnetwork_region
  project = var.project_id
}

module "custom-network" {
  source       = "../modules/gcp-network"
  count        = var.create_network ? 1 : 0
  project_id   = var.project_id
  network_name = var.network_name
  create_psa   = true

  subnets = [
    {
      subnet_name           = var.subnetwork_name
      subnet_ip             = var.subnetwork_cidr
      subnet_region         = var.subnetwork_region
      subnet_private_access = var.subnetwork_private_access
      description           = var.subnetwork_description
    }
  ]
}

locals {
  network_name    = var.create_network ? module.custom-network[0].network_name : var.network_name
  subnetwork_name = var.create_network ? module.custom-network[0].subnets_names[0] : var.subnetwork_name
  subnetwork_cidr = var.create_network ? module.custom-network[0].subnets_ips[0] : data.google_compute_subnetwork.subnetwork[0].ip_cidr_range
  region          = length(split("-", var.cluster_location)) == 2 ? var.cluster_location : ""
  regional        = local.region != "" ? true : false
  # zone needs to be set even for regional clusters, otherwise this module picks random zones that don't have GPU availability:
  # https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/blob/af354afdf13b336014cefbfe8f848e52c17d4415/main.tf#L46 
  zone = length(split("-", var.cluster_location)) > 2 ? split(",", var.cluster_location) : split(",", local.gpu_l4_t4_location[local.region])
  # Update gpu_pools with node_locations according to region and zone gpu availibility, if not provided
  gpu_pools = [for elm in var.gpu_pools : (local.regional && contains(keys(local.gpu_l4_t4_location), local.region) && elm["node_locations"] == "") ? merge(elm, { "node_locations" : local.gpu_l4_t4_location[local.region] }) : elm]
}


## create public GKE standard
module "public-gke-standard-cluster" {
  count      = var.create_cluster && !var.private_cluster && !var.autopilot_cluster ? 1 : 0
  source     = "../modules/gke-standard-public-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional                     = local.regional
  cluster_region                       = local.region
  cluster_zones                        = local.zone
  cluster_name                         = var.cluster_name
  cluster_labels                       = var.cluster_labels
  kubernetes_version                   = var.kubernetes_version
  release_channel                      = var.release_channel
  ip_range_pods                        = var.ip_range_pods
  ip_range_services                    = var.ip_range_services
  monitoring_enable_managed_prometheus = var.monitoring_enable_managed_prometheus
  gcs_fuse_csi_driver                  = var.gcs_fuse_csi_driver
  master_authorized_networks           = var.master_authorized_networks
  deletion_protection                  = var.deletion_protection

  ## pools config variables
  cpu_pools                   = var.cpu_pools
  enable_gpu                  = var.enable_gpu
  gpu_pools                   = local.gpu_pools
  enable_tpu                  = var.enable_tpu
  tpu_pools                   = var.tpu_pools
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
  ray_addon_enabled           = var.ray_addon_enabled
  depends_on                  = [module.custom-network]
}

## create public GKE autopilot
module "public-gke-autopilot-cluster" {
  count      = var.create_cluster && !var.private_cluster && var.autopilot_cluster ? 1 : 0
  source     = "../modules/gke-autopilot-public-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional           = local.regional
  cluster_region             = local.region
  cluster_zones              = local.zone
  cluster_name               = var.cluster_name
  cluster_labels             = var.cluster_labels
  kubernetes_version         = var.kubernetes_version
  release_channel            = var.release_channel
  ip_range_pods              = var.ip_range_pods
  ip_range_services          = var.ip_range_services
  master_authorized_networks = var.master_authorized_networks
  deletion_protection        = var.deletion_protection
  ray_addon_enabled          = var.ray_addon_enabled
  depends_on                 = [module.custom-network]
}

## create private GKE standard
module "private-gke-standard-cluster" {
  count      = var.create_cluster && var.private_cluster && !var.autopilot_cluster ? 1 : 0
  source     = "../modules/gke-standard-private-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional                     = local.regional
  cluster_region                       = local.region
  cluster_zones                        = local.zone
  cluster_name                         = var.cluster_name
  cluster_labels                       = var.cluster_labels
  kubernetes_version                   = var.kubernetes_version
  release_channel                      = var.release_channel
  ip_range_pods                        = var.ip_range_pods
  ip_range_services                    = var.ip_range_services
  monitoring_enable_managed_prometheus = var.monitoring_enable_managed_prometheus
  gcs_fuse_csi_driver                  = var.gcs_fuse_csi_driver
  deletion_protection                  = var.deletion_protection
  master_authorized_networks           = length(var.master_authorized_networks) == 0 ? [{ cidr_block = "${local.subnetwork_cidr}", display_name = "${local.subnetwork_name}" }] : var.master_authorized_networks
  master_ipv4_cidr_block               = var.master_ipv4_cidr_block
  ray_addon_enabled                    = var.ray_addon_enabled

  ## pools config variables
  cpu_pools                   = var.cpu_pools
  enable_gpu                  = var.enable_gpu
  gpu_pools                   = local.gpu_pools
  enable_tpu                  = var.enable_tpu
  tpu_pools                   = var.tpu_pools
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
  depends_on                  = [module.custom-network]
}

## create private GKE autopilot
module "private-gke-autopilot-cluster" {
  count      = var.create_cluster && var.private_cluster && var.autopilot_cluster ? 1 : 0
  source     = "../modules/gke-autopilot-private-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional           = local.regional
  cluster_region             = local.region
  cluster_zones              = local.zone
  cluster_name               = var.cluster_name
  cluster_labels             = var.cluster_labels
  kubernetes_version         = var.kubernetes_version
  release_channel            = var.release_channel
  ip_range_pods              = var.ip_range_pods
  ip_range_services          = var.ip_range_services
  master_authorized_networks = length(var.master_authorized_networks) == 0 ? [{ cidr_block = "${local.subnetwork_cidr}", display_name = "${local.subnetwork_name}" }] : var.master_authorized_networks
  master_ipv4_cidr_block     = var.master_ipv4_cidr_block
  deletion_protection        = var.deletion_protection
  ray_addon_enabled          = var.ray_addon_enabled

  depends_on = [module.custom-network]
}


## configure cloud NAT for private GKE
module "cloud-nat" {
  source        = "terraform-google-modules/cloud-nat/google"
  version       = "5.0.0"
  count         = var.create_network && var.private_cluster ? 1 : 0
  region        = local.region
  project_id    = var.project_id
  create_router = true
  router        = "${var.network_name}-router"
  name          = "cloud-nat-${var.network_name}-router"
  network       = module.custom-network[0].network_name
}
