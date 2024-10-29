# RAG on GKE

This is a sample to deploy a Retrieval Augmented Generation (RAG) application on GKE. 

The latest recommended release is branch release-1.1.

# What is RAG?

[RAG](https://cloud.google.com/blog/products/ai-machine-learning/rag-with-databases-on-google-cloud) is a popular approach for boosting the accuracy of LLM responses, particularly for domain specific or private data sets.

RAG uses a semantically searchable knowledge base (like vector search) to retrieve relevant snippets for a given prompt to provide additional context to the LLM. Augmenting the knowledge base with additional data is typically cheaper than fine tuning and is more scalable when incorporating current events and other rapidly changing data spaces.

### RAG on GKE Architecture
1. A GKE service endpoint serving [Hugging Face TGI inference](https://huggingface.co/docs/text-generation-inference/en/index) using `mistral-7b`.
2. [Cloud SQL `pgvector` instance](https://github.com/pgvector/pgvector) with vector embeddings generated from an input dataset.
3. A [Ray](https://docs.ray.io/en/latest/ray-overview/getting-started.html) cluster running on GKE that runs jobs to generate embeddings and populate the vector DB.
5. A [Jupyter](https://docs.jupyter.org/en/latest/) notebook running on GKE that reads the dataset using GCS fuse driver integrations and runs a Ray job to populate the vector DB.
3. A front end chat interface running on GKE that prompts the inference server with context from the vector DB.

This tutorial walks you through installing the RAG infrastructure in a GCP project, generating vector embeddings for a sample [Kubernetes Docs](https://github.com/dohsimpson/kubernetes-doc-pdf) dataset and prompting the LLM with context.

# Prerequisites

### Install tooling (required)

Install the following on your computer:
* [Kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
* [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
* [Helm](https://helm.sh/docs/intro/install/)
* [Gcloud](https://cloud.google.com/sdk/docs/install)

### Bring your own cluster (optional)

By default, this tutorial creates a cluster on your behalf. We highly recommend following the default settings.

If you prefer to manage your own cluster, set `create_cluster = false` and make sure the `network_name` is set to your cluster's network in the [Installation section](#installation). Creating a long-running cluster may be better for development, allowing you to iterate on Terraform components without recreating the cluster every time.

Use gcloud to create a GKE Autopilot cluster. Note that RAG requires the latest Autopilot features, available on the latest versions of 1.28 and 1.29.

```
gcloud container clusters create-auto rag-cluster \
  --location us-central1 \
  --cluster-version 1.28
```

### Bring your own VPC (optional)

By default, this tutorial creates a new network on your behalf with [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect) already enabled. We highly recommend following the default settings.

If you prefer to use your own VPC, set `create_network = false` in the in the [Installation section](#installation). This also requires enabling [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect) for your VPC. Without Private Service Connect, the RAG components cannot connect to the vector DB:

1. [Create an IP allocation](https://cloud.google.com/vpc/docs/configure-private-services-access#procedure)

2. [Create a private connection](https://cloud.google.com/vpc/docs/configure-private-services-access#creating-connection).

# Installation

This section sets up the RAG infrastructure in your GCP project using Terraform.

**NOTE:** Terraform keeps state metadata in a local file called `terraform.tfstate`. Deleting the file may cause some resources to not be cleaned up correctly even if you delete the cluster. We suggest using `terraform destroy` before reapplying/reinstalling.

1. `cd ai-on-gke/applications/rag`

2. Edit `workloads.tfvars` to set your project ID, location, cluster name, and GCS bucket name. Ensure the `gcs_bucket` name is globally unique (add a random suffix). Optionally, make the following changes:
    * (Recommended) [Enable authenticated access](#configure-authenticated-access-via-iap-recommended) for JupyterHub, frontend chat and Ray dashboard services.
    * (Optional) Set a custom `kubernetes_namespace` where all k8s resources will be created.
    * (Optional) Set `autopilot_cluster = false` to deploy using GKE Standard.
    * (Optional) Set `create_cluster = false` if you are bringing your own cluster. If using a GKE Standard cluster, ensure it has an L4 nodepool with autoscaling and node autoprovisioning enabled. You can simplify setup by following the Terraform instructions in [`infrastructure/README.md`](https://github.com/GoogleCloudPlatform/ai-on-gke/blob/main/infrastructure/README.md).
    * (Optional) Set `create_network = false` if you are bringing your own VPC. Ensure your VPC has Private Service Connect enabled as described above.

3. Run `terraform init`

4. Run `terraform apply --var-file workloads.tfvars`

# Generate vector embeddings for the dataset

This section generates the vector embeddings for your input dataset. Currently, the default dataset is [Kubernetes docs](https://github.com/dohsimpson/kubernetes-doc-pdf). We will use a Jupyter notebook to generate the embeddings & populates them into the `pgvector` instance created above.

Set your the namespace, cluster name and location from `workloads.tfvars`):

```
export NAMESPACE=rag
export CLUSTER_LOCATION=us-east4
export CLUSTER_NAME=rag-cluster
```

Connect to the GKE cluster:

```
gcloud container clusters get-credentials ${CLUSTER_NAME} --location=${CLUSTER_LOCATION}
```

1. Connect and login to JupyterHub:
   * If IAP is disabled (`jupyter_add_auth = false`):
        - Port forward to the JupyterHub service: `kubectl port-forward service/proxy-public -n ${NAMESPACE} 8081:80 &`
        - Go to `localhost:8081` in a browser
        - Login with these credentials:
            * username: admin
            * password: use `terraform output jupyterhub_password` to fetch the password value
   * If IAP is enabled (`jupyter_add_auth = true`):
        - Fetch the domain: `terraform output jupyterhub_uri`
        - If you used a custom domain, ensure you configured your DNS as described above. 
        - Verify the domain status is `Active`:
            - `kubectl get managedcertificates jupyter-managed-cert -n ${NAMESPACE} --output jsonpath='{.status.domainStatus[0].status}'`
            - Note: This can take up to 20 minutes to propagate.
        - Once the domain status is Active, go to the domain in a browser and login with your Google credentials.
        - To add additional users to your JupyterHub application, go to [Google Cloud Platform IAP](https://console.cloud.google.com/security/iap), select the `rag/proxy-public` service and add principals with the role `IAP-secured Web App User`.

2. Load the notebook:
    - Once logged in to JupyterHub, choose the `CPU` preset with `Default` storage. 
    - Click [File] -> [Open From URL] and paste: `https://raw.githubusercontent.com/GoogleCloudPlatform/ai-on-gke/main/applications/rag/example_notebooks/rag-data-ingest-with-kubernetes-docs.ipynb`


3. Generate vector embeddings: Run all the cells in the notebook to generate vector embeddings for the [Kubernetes documentation](https://github.com/dohsimpson/kubernetes-doc-pdf) and store them in the `pgvector` CloudSQL instance using a Ray Job.

# Launch the frontend chat interface

1. Connect to the frontend:
    * If IAP is disabled (`frontend_add_auth = false`):
        - Port forward to the frontend service: `kubectl port-forward service/rag-frontend -n ${NAMESPACE} 8080:8080 &`
        - Go to `localhost:8080` in a browser
    * If IAP is enabled (`frontend_add_auth = true`):
        - Fetch the domain: `terraform output frontend_uri`
        - If you used a custom domain, ensure you configured your DNS as described above.
        - Verify the domain status is `Active`:
            - `kubectl get managedcertificates frontend-managed-cert -n ${NAMESPACE} --output jsonpath='{.status.domainStatus[0].status}'`
            - Note: This can take up to 20 minutes to propagate.
        - Once the domain status is Active, go to the domain in a browser and login with your Google credentials.
        - To add additional users to your frontend application, go to [Google Cloud Platform IAP](https://console.cloud.google.com/security/iap), select the `rag/rag-frontend` service and add principals with the role `IAP-secured Web App User`.
2. Prompt the LLM
    * Start chatting! This will fetch context related to your prompt from the vector embeddings in the `pgvector` CloudSQL instance, augment the original prompt with the context & query the inference model (`mistral-7b`) with the augmented prompt.

# Configure authenticated access via IAP (recommended)

We recommend you configure authenticated access via IAP for your services.

1) Make sure the [OAuth Consent Screen](https://developers.google.com/workspace/guides/configure-oauth-consent#configure_oauth_consent) is configured for your project. Ensure `User type` is set to `Internal`.
2) Make sure [Policy for Restrict Load Balancer Creation Based on Load Balancer Types](https://cloud.google.com/load-balancing/docs/org-policy-constraints) allows EXTERNAL_HTTP_HTTPS.
3) Set the following variables in `workloads.tfvars`:
    * `jupyter_add_auth = true`
    * `frontend_add_auth = true`
    * `ray_dashboard_add_auth = true`
4) Allowlist principals for your services via `jupyter_members_allowlist`, `frontend_members_allowlist` and `ray_dashboard_members_allowlist`.
5) Configure custom domains names via `jupyter_domain`, `frontend_domain` and `ray_dashboard_domain` for your services. 
6) Configure DNS records for your custom domains:
    - [Register a Domain on Google Cloud Domains](https://cloud.google.com/domains/docs/register-domain#registering-a-domain) or use a domain registrar of your choice.
    - Set up your DNS service to point to the public IP
        * Run `terraform output frontend_ip_address` to get the public ip address of frontend, and add an A record in your DNS configuration to point to the public IP address.
        * Run `terraform output jupyterhub_ip_address` to get the public ip address of jupyterhub, and add an A record in your DNS configuration to point to the public IP address.
        * Run `terraform output ray_dashboard_ip_address` to get the public ip address of ray dashboard, and add an A record in your DNS configuration to point to the public IP address.
    - Add an A record: If the DNS service of your domain is managed by [Google Cloud DNS managed zone](https://cloud.google.com/dns/docs/zones), there are two options to add the A record:
        1. Go to https://console.cloud.google.com/net-services/dns/zones, select the zone and click ADD STANDARD, fill in your domain name and public IP address.
        2. Run `gcloud dns record-sets create <domain address>. --zone=<zone name> --type="A" --ttl=<ttl in seconds> --rrdatas="<public ip address>"`

# Cleanup

1. Run `terraform destroy --var-file="workloads.tfvars"`
    - Network deletion issue: `terraform destroy` fails to delete the network due to a known issue in the GCP provider. For now, the workaround is to manually delete it.

# Troubleshooting

Set your the namespace, cluster name and location from `workloads.tfvars`:

```
export NAMESPACE=rag
export CLUSTER_LOCATION=us-central1
export CLUSTER_NAME=rag-cluster
```

Connect to the GKE cluster:

```
gcloud container clusters get-credentials ${CLUSTER_NAME} --location=${CLUSTER_LOCATION}
```

1. Troubleshoot Ray job failures:
    - If the Ray actors fail to be scheduled, it could be due to a stockout or quota issue.
        - Run `kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=kuberay`. There should be a Ray head and Ray worker pod in `Running` state. If your ray pods aren't running, it's likely due to quota or stockout issues. Check that your project and selected `cluster_location` have L4 GPU capacity.
    - Often, retrying the Ray job submission (the last cell of the notebook) helps.
    - The Ray job may take 15-20 minutes to run the first time due to environment setup.

2. Troubleshoot IAP login issues:
    - Verify the cert is Active:
        - For JupyterHub `kubectl get managedcertificates jupyter-managed-cert -n ${NAMESPACE} --output jsonpath='{.status.domainStatus[0].status}'`
        - For the frontend: `kubectl get managedcertificates frontend-managed-cert -n ${NAMESPACE} --output jsonpath='{.status.domainStatus[0].status}'`
    - Verify users are allowlisted for JupyterHub or frontend services:
        - JupyterHub: Go to [Google Cloud Platform IAP](https://console.cloud.google.com/security/iap), select the `rag/proxy-public` service and check if the user has role `IAP-secured Web App User`.
        - Frontend: Go to [Google Cloud Platform IAP](https://console.cloud.google.com/security/iap), select the `rag/rag-frontend` service and check if the user has role `IAP-secured Web App User`.
    - Org error:
        - The [OAuth Consent Screen](https://developers.google.com/workspace/guides/configure-oauth-consent#configure_oauth_consent) has `User type` set to `Internal` by default, which means principals external to the org your project is in cannot log in. To add external principals, change `User type` to `External`.

3. Troubleshoot `terraform apply` failures:
    - Inference server (`mistral`) fails to deploy:
        - This usually indicates a stockout/quota issue. Verify your project and chosen `cluster_location` have L4 capacity.
    - GCS bucket already exists:
        - GCS bucket names have to be globally unique, pick a different name with a random suffix.
    - Cloud SQL instance already exists:
        - Ensure the `cloudsql_instance` name doesn't already exist in your project.
    - GMP operator webhook connection refused:
        - This is a rare, transient error. Run `terraform apply` again to resume deployment.

4. Troubleshoot `terraform destroy` failures:
    - Network deletion issue:
        - `terraform destroy` fails to delete the network due to a known issue in the GCP provider. For now, the workaround is to manually delete it.

5. Troubleshoot error: `Repo model mistralai/Mistral-7B-Instruct-v0.1 is gated. You must be authenticated to access it.` for the pod of deployment `mistral-7b-instruct`.

   The error is because the RAG deployments uses `Mistral-7B-instruct` which is now a gated model on Hugging Face. Deployments fail as they require a Hugging Face authentication token, which is not part of the current workflow.
   While we are actively working on long-term fix. This is how to workaround the error:
    - Use [the guide](https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-gemma-gpu-tgi#generate-token) as a reference to create an access token.
    - Go to the [model card](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.1) in Hugging Face and click "Agree and access repository"
    - Create [a secret](https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-gemma-gpu-vllm#create_a_kubernetes_secret_for_hugging_face_credentials) as noted in with the Hugging Face credential called `hf-secret` in the name space where your `mistral-7b-instruct` deployment is running.
    - Add the following entry to `env` within the deployment `mistral-7b-instruct` via `kubectl edit`.

```
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-secret
              key: hf_api_token
```

