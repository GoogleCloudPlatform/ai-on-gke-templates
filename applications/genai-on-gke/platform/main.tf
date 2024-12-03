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

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "project_services" {
  for_each                   = toset(var.services)
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = var.service_config.disable_on_destroy
  disable_dependent_services = var.service_config.disable_dependent_services
}


module "custom-network" {
  source       = "terraform-google-modules/network/google"
  version      = "8.0.0"
  count        = var.create_network ? 1 : 0
  project_id   = var.project_id
  network_name = var.network_name

  subnets = [
    {
      subnet_name           = var.subnetwork_name
      subnet_ip             = var.subnetwork_cidr
      subnet_region         = var.subnetwork_region
      subnet_private_access = var.subnetwork_private_access
      description           = var.subnetwork_description
    }
  ]

  secondary_ranges = var.network_secondary_ranges
  #firewall_rules = var.firewall_rules
}

locals {
  network_name    = var.create_network ? module.custom-network[0].network_name : var.network_name
  subnetwork_name = var.create_network ? module.custom-network[0].subnets_names[0] : var.subnetwork_name
}

## create public GKE standard
module "public-gke-standard-cluster" {
  depends_on = [
    google_project_service.project_services
  ]
  count      = var.create_cluster && !var.private_cluster && !var.autopilot_cluster ? 1 : 0
  source     = "../../../modules/gke-standard-public-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional                     = var.cluster_regional
  cluster_name                         = var.cluster_name
  cluster_labels                       = var.cluster_labels
  kubernetes_version                   = var.kubernetes_version
  cluster_region                       = var.cluster_region
  cluster_zones                        = var.cluster_zones
  ip_range_pods                        = var.ip_range_pods
  ip_range_services                    = var.ip_range_services
  monitoring_enable_managed_prometheus = var.monitoring_enable_managed_prometheus
  master_authorized_networks           = var.master_authorized_networks

  ## pools config variables
  cpu_pools                   = var.cpu_pools
  enable_gpu                  = var.enable_gpu
  gpu_pools                   = var.gpu_pools
  enable_tpu                  = var.enable_tpu
  tpu_pools                   = var.tpu_pools
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
}

## create public GKE autopilot
module "public-gke-autopilot-cluster" {
  count = var.create_cluster && !var.private_cluster && var.autopilot_cluster ? 1 : 0
  depends_on = [
    google_project_service.project_services
  ]
  source     = "../../../modules/gke-autopilot-public-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional           = var.cluster_regional
  cluster_name               = var.cluster_name
  cluster_labels             = var.cluster_labels
  kubernetes_version         = var.kubernetes_version
  cluster_region             = var.cluster_region
  cluster_zones              = var.cluster_zones
  ip_range_pods              = var.ip_range_pods
  ip_range_services          = var.ip_range_services
  master_authorized_networks = var.master_authorized_networks
}

## create private GKE standard
module "private-gke-standard-cluster" {
  count = var.create_cluster && var.private_cluster && !var.autopilot_cluster ? 1 : 0
  depends_on = [
    google_project_service.project_services
  ]
  source     = "../../../modules/gke-standard-private-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional                     = var.cluster_regional
  cluster_name                         = var.cluster_name
  cluster_labels                       = var.cluster_labels
  kubernetes_version                   = var.kubernetes_version
  cluster_region                       = var.cluster_region
  cluster_zones                        = var.cluster_zones
  ip_range_pods                        = var.ip_range_pods
  ip_range_services                    = var.ip_range_services
  monitoring_enable_managed_prometheus = var.monitoring_enable_managed_prometheus
  master_authorized_networks           = var.master_authorized_networks
  master_ipv4_cidr_block               = var.master_ipv4_cidr_block
  ## pools config variables
  cpu_pools                   = var.cpu_pools
  enable_gpu                  = var.enable_gpu
  gpu_pools                   = var.gpu_pools
  enable_tpu                  = var.enable_tpu
  tpu_pools                   = var.tpu_pools
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
}

## create private GKE autopilot
module "private-gke-autopilot-cluster" {
  count = var.create_cluster && var.private_cluster && var.autopilot_cluster ? 1 : 0
  depends_on = [
    google_project_service.project_services
  ]
  source     = "../../../modules/gke-autopilot-private-cluster"
  project_id = var.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional           = var.cluster_regional
  cluster_name               = var.cluster_name
  cluster_labels             = var.cluster_labels
  kubernetes_version         = var.kubernetes_version
  cluster_region             = var.cluster_region
  cluster_zones              = var.cluster_zones
  ip_range_pods              = var.ip_range_pods
  ip_range_services          = var.ip_range_services
  master_authorized_networks = var.master_authorized_networks
}


## configure cloud NAT for private GKE
module "cloud-nat" {
  source        = "terraform-google-modules/cloud-nat/google"
  version       = "5.0.0"
  count         = var.create_network && var.private_cluster ? 1 : 0
  region        = var.region
  project_id    = var.project_id
  create_router = true
  router        = "${var.network_name}-router"
  name          = "cloud-nat-${var.network_name}-router"
  network       = module.custom-network[0].network_name
}
