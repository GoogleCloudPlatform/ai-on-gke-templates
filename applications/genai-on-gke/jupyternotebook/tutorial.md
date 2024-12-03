

## Let's get started!

Welcome to the Cloudshell tutorial for AI on GKE!

This guide will show you how to prepare a GKE cluster and install the AI applications on GKE. It'll also walk you through the configuration files that can be provided with custom inputs and commands that will complete the tutorial.

**Time to complete**: About 5 minutes

**Prerequisites**: GCP project linked with a Cloud Billing account

To begin, click **Start**.

## What is AI-on-GKE

This tutorial Terraform & Cloud Build to provision the infrastructure as well as deploy the workloads

## Architecture
Defaults:
- Installs CUDA drivers for nvidia tesla t4 GPU machines
- Deploy Helm Chart for Jupyter hub with an option to change the cpu, memory , gpu etc.

You'll be performing the following activities:

1. Set project-id for gcloud CLI
2. Update terraform variable values to create infrastructure
3. Update terraform variable values to provide workload configuration
4. Create a GCS bucket to store terraform state
5. Terraform plan and apply


To get started, click **Next**.

## Step 0: Set your project
To set your Cloud Platform project for this terminal session use:
```bash
gcloud config set project [PROJECT_ID]
```
All the resources will be created in this project

## Step 1: Provide PLATFORM Inputs Parameters for Terraform

Here on step 1 you need to update the  terraform variables  file (located in ./jupyternotebook/variables.tf) to provide the input parameters to allow terraform code execution to provision GKE resources. This will include the input parameters in the form of key value pairs. Update the values as per your requirements.

<walkthrough-editor-open-file filePath="./jupyternotebook/variables.tf"> Open variables.tf
</walkthrough-editor-open-file>

Update `project_id` `region` `cluster_name` and review the other default values.

**Tip**: Click the highlighted text above to open the file in your cloudshell editor.






## Step 2: Configure Terraform GCS backend

You can also configure the GCS bucket to persist the terraform state file for further usage. To configure the terraform backend you need to have a GCS bucket already created.


### Create GCS Bucket
In case you don't have a GCS bucket already, you can create using terraform or gcloud command as well. Refer below for the gcloud command line to create a new GCS bucket.
```bash
gcloud storage buckets create gs://BUCKET_NAME
```
**Tip**: Click the copy button on the side of the code box to paste the command in the Cloud Shell terminal to run it.


### Modify  Terraform State Backend

Modify the ./platform/backend.tf and uncomment the code and update the backend bucket name.
<walkthrough-editor-open-file filePath="./jupyternotebook/backend.tf"> Open backend.tf
</walkthrough-editor-open-file>

After changes file will look like below:
```terraform
terraform {
 backend "gcs" {
   bucket  = "BUCKET_NAME"
   prefix  = "terraform/state"
 }
}
```

Refer [here](https://cloud.google.com/docs/terraform/resource-management/store-state) for more details.



## Step 3: Run Terrafrom Plan and Apply

Run Terrform plan and check the resources to be created , please make changes if any required to terraform files as required and then run terrafrom apply
```bash
terraform plan
terraform apply
```



## Step 4: Delete resources created

You can now delete the resources


```bash
terraform destroy
```

## Congratulations

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

You're all set!

You can now access your cluster and applications.
