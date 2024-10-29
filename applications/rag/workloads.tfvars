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

project_id      = "<your project ID>"
create_network  = true         # Creates a new VPC for your cluster. Disable to use an existing network.
network_name    = "ml-network" # Creates a network named ml-network by default. If using an existing VPC, ensure you follow the README instructions to enable Private Service Connect for your VPC.
subnetwork_cidr = "10.100.0.0/16"

create_cluster    = true # Creates a GKE cluster in the specified network.
cluster_name      = "<cluster-name>"
cluster_location  = "us-central1"
autopilot_cluster = true
private_cluster   = false

## GKE environment variables
kubernetes_namespace = "ai-on-gke"

# The bucket name must be globally unique (across all of Google Cloud).
# To verify, check that `gcloud storage buckets describe gs://<bucketname>` returns a 404.
create_gcs_bucket = true
gcs_bucket        = "rag-data-<username>"

# Ensure the instance name is unique to your project.
cloudsql_instance = "pgvector-instance"

## Service accounts

# Creates a google service account & k8s service account & configures workload identity with appropriate permissions.
ray_service_account             = "ray-rag-sa"
enable_grafana_on_ray_dashboard = false

# Creates a google service account & k8s service account & configures workload identity with appropriate permissions.
rag_service_account = "rag-sa"

# Creates a google service account & k8s service account & configures workload identity with appropriate permissions.
jupyter_service_account = "jupyter-rag-sa"

## Embeddings table name - change this to the TABLE_NAME used in the notebook.
dataset_embeddings_table_name = "rag_embeddings_db"

##############################################################################################################
# If you don't want to enable IAP authenticated access for your endpoints, ignore everthing below this line. #
##############################################################################################################

# NOTE: If enabling IAP by setting the variables below to true, first configure your OAuth consent screen: (https://developers.google.com/workspace/guides/configure-oauth-consent#configure_oauth_consent).
# Ensure 'User type' is 'Internal'.

## Jupyter IAP Settings
jupyter_add_auth          = false                                                                 # Set to true to enable authenticated access via IAP.
jupyter_domain            = "jupyter.example.com"                                                 # Custom domain for ingress resource and ssl certificate. 
jupyter_members_allowlist = "user:<email>,group:<email>,serviceAccount:<email>,domain:google.com" # Allowlist principals for access.

## Frontend IAP Settings
frontend_add_auth          = false                                                                 # Set to true to enable authenticated access via IAP.
frontend_domain            = "frontend.example.com"                                                # Custom domain for ingress resource and ssl certificate.
frontend_members_allowlist = "user:<email>,group:<email>,serviceAccount:<email>,domain:google.com" # Allowlist principals for access.

## Ray Dashboard IAP Settings
ray_dashboard_add_auth          = false                                                                 # Set to true to enable authenticated access via IAP.
ray_dashboard_domain            = "ray.example.com"                                                     # Custom domain for ingress resource and ssl certificate. 
ray_dashboard_members_allowlist = "user:<email>,group:<email>,serviceAccount:<email>,domain:google.com" # Allowlist principals for access.
