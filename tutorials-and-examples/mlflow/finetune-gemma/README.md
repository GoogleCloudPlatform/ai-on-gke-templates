# Fine-tune gemma-2-9b and track as an experiment is MLFlow
Data scientists often run a lot of experiments and it's essential to be sure that the best run won't be lost in numerous experiments. MLFlow helps to track experiments, datasets, metrics, and other data. GKE clusters can provide a lot of resources on demand.

In this tutorial, we will demonstrate how to deploy MLFlow on GKE cluster and set it up for seamless model deployment.

## The tutorial overview
In this tutorial we will fine-tune gemma2-9b using LoRA as an experiment in MLFlow. We will deploy MLFlow on a GKE cluster and set up MLFlow to store artifacts inside a GCS bucket. In the end, we will deploy a fine-tuned model using KServe.

## Before you begin
Ensure you have a GCP project with a billing account. Enable the following APIs for your project:
- [GKE](https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?inv=1&invt=Abma5w&project=cvdjango&returnUrl=/kubernetes/overview/get-started?inv%3D1%26invt%3DAbma5w%26project%3Dcvdjango)
- [Artifact Registry API](https://console.cloud.google.com/marketplace/product/google/artifactregistry.googleapis.com?returnUrl=/artifacts?invt%3DAbma5w%26inv%3D1%26project%3Dcvdjango&project=cvdjango&inv=1&invt=Abma5w&flow=gcp)

Ensure you have the following tools installed on your workstation:
```
gcloud CLI
gcloud kubectl
terraform
helm
```
CLI. If you previously installed the gcloud CLI, get the latest version by running `gcloud components update`

## Set up
If you don’t have a GCP project, you have to create one. Ensure that your project has access to GKE.

Run these commands to authenticate:
```bash
gcloud auth login
gcloud auth application-default login
```

Run `cd terraform-gke-cluster` and adjust in the `example_environments.tfvars` file the following variables:
- `project_id` – your GCP project id.
- `cluster_name` – any name for your cluster.
- `kubernetes_namespace` – any GKE environment variable namespace.
Run these commands to create your GKE cluster:
```bash
terraform init
terraform plan -var-file=example_environments.tfvars  # verify is it okay
terraform apply -var-file=example_environments.tfvars # print 'yes' when asked
```

After about 10-15 minutes your cluster will be ready to go. When the cluster is ready, run this command to get your GKE cluster access token:
```bash
export KUBECONFIG=~/tutorial_gke_access_token.kube
export REGION="<REGION>"
export PROJECT_ID="<PROJECT_ID>"
export CLUSTER_NAME="<CLUSTER_NAME>"
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION --project $PROJECT_ID
```
At this point, you have your terminal session with set up kubectl. The next step is KServe installation on your GKE cluster. You can follow the official guide [here](https://kserve.github.io/website/master/admin/serverless/serverless/).

## Install MLFlow
Go to the `mlflow-configuration` directory. We will use the helm to install MLFlow. Use [This chart](https://artifacthub.io/packages/helm/bitnami/mlflow) to install MLFlow with necessary configuration.

Since we want to access our model from MLFlow UI and deploy it using KServe easily, we need to specify environment variables for MLFlow so it could use GCS bucket as artifact storage. Go to the Google Cloud Console and create a GCS bucket. Then create a key for the service account used by your cluster and save it in your current working directory as `credentials.json`.

You can find your the cluster service account email by running this command:
```bash
gcloud container clusters describe $CLUSTER_NAME \
  --region $REGION \
  --format="value(nodeConfig.serviceAccount)"
```

Run this command to create a secret inside your GKE cluster:
```bash
kubectl create secret generic gcs-credentials --from-file=gcloud-application-credentials.json=./credentials.json
```

Don’t forget to give your service account permissions to access your GCS bucket. We also need to provide read-only access to the Artifact Registry to be able to pull Docker images to create a fine-tuning job. To access and create data in a GCS bucket should be enough `Storage Object User` role.

And go to Artifact Registry to create a new repository. Give `Artifact Reader` permission for the GKE cluster service account

Before installing the MLFlow chart, we need to adjust `values.yaml` so MLFlow could interact with the GCS bucket. Adjust the following values:
- <BUCKET_NAME> – your bucket name
- <PROJECT_ID> – your GCP project id

Install the MLFlow chart
```bash
helm install my-mlflow-release oci://registry-1.docker.io/bitnamicharts/mlflow -f values.yaml
```

The result of this command will show you how to access MLFlow UI. The output should look similar to this:
```log
...
1. Get the running pods
    kubectl get pods --namespace default -l "app.kubernetes.io/name=mlflow,app.kubernetes.io/instance=my-mlflow-release"

2. Get into a pod
    kubectl exec -ti [POD_NAME] bash

3. Execute your script as you would normally do.
MLflow Tracking Server can be accessed through the following DNS name from within your cluster:

    my-mlflow-release-tracking.default.svc.cluster.local (port 80)

To access your MLflow site from outside the cluster follow the steps below:

1. Get the MLflow URL by running these commands:

   kubectl port-forward --namespace default svc/my-mlflow-release-tracking 80:80 &
   echo "MLflow URL: http://127.0.0.1//"
...
```

Let’s check our MLFlow tracking server via UI. We can port forward MLFlow tracking service by running the command below. This process runs in background due to the `&` sign. You can stop the process by killing it (the PID is printed after running the port-forwarding command).
```bash
kubectl port-forward --namespace default svc/my-mlflow-release-tracking 8080:80 &
```

The above command will create a process that forwards ports to MLFlow tracking server. This process runs in background due to the & sign. You can stop the process by killing it (the PID is printed after running the port-forwarding command).

Check your MLFlow UI at http://127.0.0.1:8080. You should be able to see the MLFlow UI like this:
![alt text](./imgs/img0.png)

## Fine-tune gemma2-9b using LoRA
Before we start our fine-tuning job, we need to create a kubernetes secret with a huggingface API token and accept the Google license to be able to download the model weights. Go to the google/gemma-2-9b and accept the license. Then run the commands below to create huggingface secret:
```bash
export HF_TOKEN=<HF_TOKEN>
kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -
```

Now we can use MLFlow to track our fine-tuning process as an MLFlow experiment. To do so, we will define several files:
- cloudbuild.yaml to use build and push Docker image to Artifact Registry
- Dockerfile for containerization
- finetune.yaml file for GKE cluster job
- finetune.py for fine-tuning

Create an Artifact Registry Docker Repository by running the following command:
```bash
gcloud artifacts repositories create gemma \
    --project=${PROJECT_ID} \
    --repository-format=docker \
    --location=us \
    --description="Gemma Repo"
```

Now we can build our Docker image for a fine-tuning job. Run the command below:
```bash
gcloud builds submit .
```

In the end, the output should look like this:
```log
DONE
-------------------------------------------------------------------------------------------------------------------------------------
ID                                    CREATE_TIME                DURATION  SOURCE                                                                                           IMAGES                                                                 STATUS
44ff24d5-042f-49e9-9666-5d00a6057e63  2025-01-14T09:45:13+00:00  12M43S    gs://akvelon-gke-aieco_cloudbuild/source/1736847911.742098-6bbf01cd346f41aeb96cdd0ceb658181.tgz  us-docker.pkg.dev/akvelon-gke-aieco/gemma/finetune-gemma-mlflow:1.0.0  SUCCESS
```

In the `finetune.yaml` file you can see the crucial MLFlow environment variables:
- `MLFLOW_URI`: for connecting to the MLFlow tracking server. We set it to `http://my-mlflow-release-5-tracking:80`, which is internal GKE cluster URI.
- `MLFLOW_ARTIFACT_URI`: for connecting experiments to our GCS bucket. You should specify it like `gs://<BUCKET_NAME>/<ANY_EXISTING_PATH>`.
- `MLFLOW_EXPERIMENT_NAME`: this is an experiment name. If you want to start a fine-tuning job as a new experiment, then change this variable.

Then run this command to create fine-tuning job:
```bash
kubectl apply -f finetune.yaml
```

You can review your pods by running the following command.
```bash
kubectl get pods -w
```

After the status of your pod is Running, you can check the running logs via this command:
```bash
kubectl logs <POD_NAME> -f
```
The output should look like this:
```log
{'loss': 0.8569, 'grad_norm': 1.615104079246521, 'learning_rate': 1.0277984159122733e-07, 'epoch': 0.99}
{'loss': 0.8612, 'grad_norm': 2.9606473445892334, 'learning_rate': 8.391511416816489e-09, 'epoch': 1.0}
{'train_runtime': 247.4258, 'train_samples_per_second': 4.042, 'train_steps_per_second': 2.021, 'train_loss': 1.1304109792709351, 'epoch': 1.0}
100%|██████████| 500/500 [04:07<00:00,  2.02it/s]
Loading checkpoint shards: 100%|██████████| 3/3 [00:03<00:00,  1.32s/it]
🏃 View run funny-mare-232 at: http://my-mlflow-release-tracking:80/#/experiments/1/runs/31c95f20219946b9934b2f26e4a863af
🧪 View experiment at: http://my-mlflow-release-tracking:80/#/experiments/1
```

Or you can go to your MLFlow and check metrics.

## Model registry
After the fine-tuning job is finished, you can check the result in MLFlow UI.
![alt text](./imgs/img1.png)

Find your experiment and go to the artifacts tab.
![alt text](./imgs/img2.png)

Here you can register your model.
![alt text](./imgs/img3.png)

Now you have registered an ML model in MLFlow!
![alt text](./imgs/img4.png)

## Deployment
Go to the `deploy-gemma2` directory. In this section we will use KServe to deploy our fine-tuned model. Before deployment, we have to prepare the environment for the mlserver. Since [seldonio/mlserver](https://hub.docker.com/r/seldonio/mlserver/tags)'s libraries might be outdated, we can provide our custom environment with libraries that we need (you can read more detail [here](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver)).

First of all, we have to give our default service account additional permissions, in order to use [gcsfuse](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver) for mounting our custom environment. Run the commands below:
```bash
gcloud storage buckets add-iam-policy-binding gs://dima_mlflow_artifact_storage \
    --member "principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/default/sa/default" \
    --role "roles/storage.objectAdmin"

gcloud storage buckets add-iam-policy-binding gs://dima_mlflow_artifact_storage \
    --member "principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/default/sa/default" \
    --role "roles/storage.admin"
```

You can see that we have a `conda-configs` directory. Inside this directory is a `yaml` file that will be used to create our custom environment. Create a configmap with this `environment.yaml` by running this command below:
```bash
kubectl create configmap conda-requirements --from-file=conda-configs
```

Before you run environment creation job, you need to adjust values in the `create-tarball.yaml`:
- <YOUR_BUCKET_NAME> – you should paste your bucket name here.

Now we can run our environment creation job:
```bash
kubectl apply -f create-tarball.yaml
```

After the job is done, you can see that your bucket now has `mlflo-gemma2-env.tar.gz` tarball. We will use it in the `deploy.yaml`. Run the command below:
```bash
kubectl apply -f deploy.yaml
```

You can check deployment status by this command:
```bash
kubectl get inferenceservices -w
```

The output should look like this:
```log
NAME                                  URL                                                              READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
gemma-2-9b-finetuned                  http://gemma-2-9b-finetuned-default.example.com                  True                                                                  4m34s
```

When the inferenceservice gets the `READY=True`, you can invoke fine-tuned model using these commands below to access the model:
```bash
SERVICE_HOSTNAME=$(kubectl get inferenceservice gemma-2-9b-finetuned -o jsonpath='{.status.url}' | cut -d "/" -f 3)
INGRESS_HOST=127.0.0.1
INGRESS_PORT=8081
kubectl port-forward -n istio-system svc/istio-ingressgateway $INGRESS_PORT:80 &
```

And the model call command:
```bash
curl -v \
  -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @./input.json \
  http://${INGRESS_HOST}:${INGRESS_PORT}/v2/models/gemma-2-9b-finetuned/infer | jq
```

The output should be like this:
```json
{
  "model_name": "gemma-2-9b-finetuned-1",
  "id": "d0d248ea-1b4b-42a0-bf96-14b95819daac",
  "parameters": {
    "content_type": "str"
  },
  "outputs": [
    {
      "name": "output-1",
      "shape": [
        1,
        1
      ],
      "datatype": "BYTES",
      "parameters": {
        "content_type": "str"
      },
      "data": [
        "Question: What is the total number of attendees with age over 30 at kubecon eu? Context: CREATE TABLE attendees (name VARCHAR, age INTEGER, kubecon VARCHAR)\nContext: CREATE TABLE attendees (name VARCHAR, age INTEGER, kubecon VARCHAR)\nAnswer:"
      ]
    }
  ]
}
```

## Clean up
To clean up, you need to go to the `terraform-gke-cluster` directory and run the following command:
```bash
terraform destroy -var-file=example_environment.tfvars
```

And delete your GCS bucket where you stored everything during the guide.
