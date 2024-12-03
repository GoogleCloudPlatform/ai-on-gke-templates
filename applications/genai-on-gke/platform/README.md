# Setup Infra

Platform module (to be renamed to Infra), creates the GKE cluster & other related resources for the AI applications / workloads to be deployed on them. 

Update the ```platform.tfvars``` file with the required configuration. Kindly refer to ```tfvars_examples``` for sample configuration.


## Prerequisites

For the GCP project where the infra resources are being created, the following prerequisites should  be met
- Billing is enabled
- GPU quotas in place
- 

Following service APIs are enabled, 
- container.googleapis.com
- gkehub.googleapis.com

if not already enabled, use the following command:
```
gcloud services enable container.googleapis.com gkehub.googleapis.com
```
## Network Connectivity

### Private GKE Cluster with internal endpoint
Default config in ```platform.tfvars``` creates a private GKE cluster with internal endpoints & cluster is added to project-scoped Anthos fleet.
For admin access to cluster, Anthos Connect Gateway is used. 

### Private GKE Cluster with external endpoint
Clusters with external endpoints can be accessed by configuing Autorized Networks. VPC network (10.100.0.0/16) is already configured for control plane authorized networks. 

## GPU Drivers
Lorum Ipsum

## Outputs
- cluster-name
- region
- project_id