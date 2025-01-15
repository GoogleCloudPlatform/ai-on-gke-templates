# Guide to Serving Mistral 7B-Instruct v0.1 on GKE Utilizing Nvidia L4-GPUs   

Learn how to serve the Mistral 7B instruct v0.1 chat model on GKE using just 1 x L4 GPU. This tutorial adapts the HF-text-generation-inference project for serving Mistral AI's model.

### Prerequisites

*   Terminal Setup: Ensure you have kubectl and gcloud installed. Using Cloud Shell is highly  recommended for its simplicity and built-in tools.
*   GPU Quota: Confirm you have the quota for at least one L4 GPU in your Google Cloud account.
*   Model Access: Secure access to the Mistral 7B model by agreeing to the terms on Hugging Face, which typically involves creating an account and accepting the model's use conditions.
*   Ensure you currently have installed a stable version of Transformers, 4.34.0 or newer.
*  (OPTIONAL) If you intend to utilize the HPA, (horizontal pod autoscaler) in order to scale for incoming requests please make sure that the 'maxReplicas' assignment in your mistral-7b.yaml HorizontalPodAutoscaler section is configured to equal or be less than the number of GPUs you have available for the deployment. Additionally, ensure that you have a DCGM (Data Center GPU Manager) NVIDIA pod configured within your Kubernetes cluster to collect GPU metrics. Look at DCGM documentation for guidance on setting up and configuring this pod properly. This is essential for the Horizontal Pod Autoscaler (HPA) to accurately scale based on GPU utilization. Without proper GPU metrics, the autoscaler won't be able to make informed scaling decisions, potentially leading to under or over-provisioning of resources. Integrate the DCGM pod within your cluster's monitoring system to provide real-time GPU performance data to the HPA.+


### GPU-Memory Allocation 
For the Mistral-7B-Instruct-v0.1 model without quantization, the memory requirement is approximately 14.2 GB. Given that an L4 GPU has 24 GB of GPU memory, a single L4 GPU is sufficient to run the model, including some overhead for operational processes. This setup ensures effective deployment on a single GPU without the need for additional resources.


### Feature-specific to Model
*  Model: Mistral-7B-instruct-v0.1, a transformer-based architecture.
*   Attention Mechanisms:
    - Grouped-Query Attention: GQA categorizes query heads into groups, with each group sharing a common key and value projection. This setup allows for three variations: GQA-1, which is similar to MQA; GQA-H, mirroring the concept of MHA; and GQA-G, an intermediate state that balances between efficiency and expressiveness. By organizing query heads into groups, GQA reduces memory overhead and allows for nuanced control over the model's performance, effectively mitigating challenges related to memory bandwidth in large context scenarios
    - Sliding-Window Attention: This attention mechanism limits the focus of the model to a nearby set of positions around each token, enhancing the model's ability to capture and utilize local contextual information more effectively, improving understanding and generation of text that relies on close proximity relationships.
    -  Byte-fallback BPE tokenizer: A tokenizer that combines byte-level encoding with Byte Pair Encoding (BPE) to ensure a balance between efficiency and coverage, allowing for the encoding of a wide range of text inputs, including those with uncommon characters or symbols, by falling back to byte-level representation when necessary.


Set your region and project:

```bash
export REGION=us-central1
export PROJECT_ID=$(gcloud config get-value project)
```

#### GKE Cluster Creation:
```bash
# Adjust if your specific setup has different requirements:
gcloud container clusters create mistral-cluster-gke  \
    --location=${REGION} \
    --node-locations=${REGION} \
    --project= ${PROJECT_ID} \
    --machine-type=n1-standard-4 \
    --no-enable-master-authorized-networks \
    --addons=GcsFuseCsiDriver \
    --num-nodes=3 \
    --min-nodes=1 \
    --max-nodes=5 \
    --enable-ip-alias \
    --enable-image-streaming \
    --enable-shielded-nodes \
    --shielded-secure-boot \
    --shielded-integrity-monitoring \
    --workload-pool=${PROJECT_ID}svc.id.goog
```

#### Node Pool with Single L4 GPU:
Create a node pool for deploying Mistral 7B with a single L4 GPU {1 x L4}:
```bash
gcloud container node-pools create mistral-gpu-pool \
    --cluster=mistral-cluster \
    --region=${REGION} \
    --project=${PROJECT_ID}} \
    --machine-type=g2-standard-12 \
    --accelerator=type=nvidia-l4,count=1,gpu-driver-version=latest \
    --ephemeral-storage-local-ssd=count=2 \
    --node-locations=${ZONE} \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=2 \
    --node-labels=accelerator=nvidia-gpu
```

#### Hugging Face Authentication:
Obtain your Hugging Face token for model access: https://huggingface.co/settings/tokens
For Hugging Face authentication and to download the Mistral model:
```bash
export HF_TOKEN=<your-token>
kubectl create secret generic mistral-demo --from-literal="HF_TOKEN=$HF_TOKEN"
```
Please use the given YAML file named mistral-7b.yaml with the provided content: Mistral 7B instruct-deployment.

Deploy Mistral 7B with the following command:
```bash
kubectl apply -f mistral-7b.yaml
```

Assess the details of your deployment using the following command (Adjust if you utilized a different name in your YAML):
```bash
kubectl describe deployment mistral-7b -n default
```

Your output should resemble the following; please make sure the details are in accordance with your declarations and deployment needs: 
```bash
Name:                   mistral-7b
Namespace:              default
CreationTimestamp:      Fri, 15 Mar 2024 11:47:53 -0700
Labels:                 <none>
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=mistral-7b
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=mistral-7b
  Containers:
   mistral-7b:
    Image:      us-docker.pkg.dev/deeplearning-platform-release/gcr.io/huggingface-text-generation-inference-cu124.2-3.ubuntu2204.py311
    Port:       8080/TCP
    Host Port:  0/TCP
    Limits:
      nvidia.com/gpu:  1
    Environment:
      MODEL_ID:   mistralai/Mistral-7B-Instruct-v0.1
      NUM_SHARD:  1
      PORT:       8080
      QUANTIZE:   bitsandbytes-nf4
    Mounts:
      /tmp from tmp (rw)
      /dev/shm from dshm (rw)
  Volumes:
   dshm:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
   tmp:
    Type:          HostPath (bare host directory volume)
    Path:          /mnt/stateful_partition/kube-ephemeral-ssd/mistral-data
    HostPathType:  
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  <none>
NewReplicaSet:   mistral-7b-7b8bd5c7f4 (1/1 replicas created)
Events:          <none>
```

Test the deployment by forwarding the port and using curl to send a prompt:

```bash
kubectl port-forward deployment/mistral-7b 8080:8080
```

#### Check for deployment and retrieve Load-Balancer external exposed ip address:
List Services: First, list all services in the namespace (assuming default namespace as per your YAML) to make sure your service is up and running.

```bash
kubectl get svc --namespace=default
```

Attach correct labels to load balancer deployment:
```bash
kubectl label service mistral-7b-service LLM_deployment=true model_LoadBalancer=true Ingress_Point=true
```

#### Generate Load Balancer Details:
To describe all services of type Load Balancer in your Kubernetes cluster, you should be able to see the details of your mistral LB here and get the ingress as well as external ip. (The external exposed ip will be important for connecting it to external services).
```bash
kubectl get services --all-namespaces -o wide | grep LoadBalancer | while read -r namespace name type cluster_ip external_ip ports age; do echo "Describing service $name in namespace $namespace:"; kubectl describe service -n $namespace $name; done
```

Your Load Balancer details should resemble the following
Describing service mistral-7b-service in namespace default:

```bash
ame:                     mistral-7b-service
Namespace:                default
Labels:                   Ingress_Point=true
                          LLM_deployment=true
                          model_LoadBalancer=true
Annotations:              cloud.google.com/neg: {"ingress":true}
Selector:                 app=mistral-7b
Type:                     LoadBalancer
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.88.55.248
IPs:                      10.88.55.248
LoadBalancer Ingress:     34.125.177.85   # This ingress serves as your external IP
Port:                     <unset>  80/TCP
TargetPort:               8080/TCP
NodePort:                 <unset>  32683/TCP
Endpoints:                10.92.3.4:8080
Session Affinity:         None
External Traffic Policy:  Cluster
Events:                   <none>

```

#### OPTIONAL: (If using HPA) Make sure HPA Horizontal Pod Autoscalar is working (Please see HPA documentation and preconfigurations needed):
Please make sure you have adjusted the yaml file appropriately.
```bash
# kubectl describe hpa mistral-7b-hpa
```

#### Test the model deployment
Interact with the Model via curl, replace ip address with your external load balancer ip obtained from the kubectl get svc --namespace=default command earlier.

```bash
# Define the instruction
instruction="INST] You are a wise, courteous, and truthful Cheshire Cat, always offering guidance through Wonderland. Your responses must be insightful and protective, avoiding any mischief, malice, or misunderstanding. Your words should never wander into realms of rudeness, unfairness, or deception. Ensure your guidance is free from any bias and shines with positivity. If a query seems like a riddle without an answer or strays too far from Wonderland's wisdom, kindly explain why it doesn't hold water in our world rather than leading someone astray. Should a question's answer elude you in the vastness of Wonderland, refrain from conjuring falsehoods. What is a secret in the gardens of Wonderland?[/INST]"

# Additional text to be concatenated with the instruction
additionalText=" The story of the killer pancake monster:"

# Combine them
fullText="$instruction$additionalText"

# Create the JSON payload
jsonPayload=$(cat <<EOF
{
  "inputs": "$fullText",
  "parameters": {
    "best_of": 1,
    "decoder_input_details": false,
    "details": false,
    "do_sample": true,
    "max_new_tokens": 400,
    "repetition_penalty": 1.03,
    "return_full_text": true,
    "seed": null,
    "stop": ["EOS", "EOSTOKEN", "ENDTOKEN", "ENDOFLINE"],

    "temperature": 0.5,
    "top_k": 10,
    "top_n_tokens": 5,
    "top_p": 0.95,
    "truncate": null,
    "typical_p": 0.95,
    "watermark": true
  },
  "stream": false
}
EOF
)

# Execute the curl command, Please replace IP with the current External(Exposed)IP of the Loadbalancer
curl -X 'POST' \
  'http://{EXTERNAL_IP}/' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d "$jsonPayload"
  
```


Measure the latency of a model deployment by timing a POST request to a model's generate endpoint, calculating the total response time and the latency per generated token. Make sure deployment latency is within tolerneces, otherwise your cluster/nodepool is misconfigured.

```bash
#### Test model deployment latency, Please make sure you differentiate hot and cold latency.
start=$(date +%s.%N)

instruction="[INST] You are a wise, courteous, and truthful Cheshire Cat, always offering guidance through Wonderland. Your responses must be insightful and protective, avoiding any mischief. Your words should never wander into realms of rudeness, unfairness, or deception. refrain from conjuring falsehoods. What is a secret in the gardens of Wonderland?[/INST]"

# Additional text to be concatenated with the instruction
additionalText=" The story of the killer pancake monster:"

# Combine them
fullText="$instruction$additionalText"

# Create the JSON payload
jsonPayload=$(cat <<EOF
{
  "inputs": "$fullText",
  "parameters": {
    "best_of": 1,
    "decoder_input_details": false,
    "details": false,
    "do_sample": true,
    "max_new_tokens": 400,
    "repetition_penalty": 1.03,
    "return_full_text": true,
    "seed": null,
    "stop": ["EOS", "EOSTOKEN", "ENDTOKEN", "ENDOFLINE"],

    "temperature": 0.5,
    "top_k": 10,
    "top_n_tokens": 5,
    "top_p": 0.95,
    "truncate": null,
    "typical_p": 0.95,
    "watermark": true
  },
  "stream": false
}
EOF
)

# Execute the curl command, Please replace IP with the current External(Exposed)IP of the Loadbalancer
curl -X 'POST' \
  'http://{EXTERNAL_IP}/' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d "$jsonPayload"

end=$(date +%s.%N)

# Extract the number of generated tokens from the response
generated_tokens=$(echo "$response" | jq '.[0].details.generated_tokens')


# If jq didn't find the field, or it's not a number, default to 1 to avoid division by zero
if ! [[ "$generated_tokens" =~ ^[0-9]+$ ]]; then
  generated_tokens=1
fi

total_latency=$(echo "$end - $start" | bc)

# Calculate latency per generated token / This is meant to calculate general latency, might vary depending on your own setup. 
latency_per_token=$(echo "scale=6; $total_latency / $generated_tokens" | bc)

echo "Total Latency: $total_latency seconds"
echo "Generated Tokens: $generated_tokens"
echo "Latency per Generated Token: $latency_per_token seconds"

```

Visit the API docs at http://localhost:8080/docs for more details.

This README provides a concise guide to deploying the Mistral 7B instruct v.01 model, listed above are key steps and adjustments needed for a general sample deployment. Ensure to replace placeholders and commands with the specific details of your GKE setup and Mistralv01-instruct model deployment.
