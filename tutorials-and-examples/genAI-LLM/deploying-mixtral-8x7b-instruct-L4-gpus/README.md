# Guide to Serving Mixtral 8x7 Model on GKE Utilizing Nvidia L4-GPUs

This guide walks you through the process of serving the Mixtral 8x7 model on Google Kubernetes Engine (GKE) leveraging Nvidia L4 GPUs. We'll adapt from the previous Mistral model deployment, focusing on a quadpod L4 GPU setup for enhanced performance.

### Prerequisites

*   Terminal Setup: Ensure kubectl and gcloud are installed. Google Cloud Shell is recommended for its ease of use and built-in tools.
*   GPU Quota: Confirm you have the quota for at least four L4 GPUs in your Google Cloud account.
*   Model Access: Secure access to the Mixtral 8x7 model by agreeing to terms on a designated platform, typically involving account creation and acceptance of use conditions.
Transformers Library: Ensure you have installed a stable version of the Transformers library, version 4.34.0 or newer.
*   HPA (Optional): If you plan to use the Horizontal Pod Autoscaler (HPA) to scale for incoming requests, ensure the 'maxReplicas' assignment in your mixtral-8x7.yaml HorizontalPodAutoscaler section is set to equal or be less than the number of GPUs available for deployment.

### GPU-Memory Allocation and Quantization Strategy
GPU-Memory Allocation and Quantization Strategy
When deploying the Mixtral 8x7 model, it's crucial to assess both the memory requirements and the computational efficiency, especially when leveraging Nvidia L4 GPUs, each with 24 GB of GPU memory. A key factor in this consideration is the use of quantization techniques to optimize model performance and memory usage.

Currently, the deployment employs 4-bit quantization (using the bitsandbytes-nf4 method), which significantly reduces the memory footprint of the model while maintaining a balance between performance and resource allocation. This quantization strategy allows the model to be efficiently served on a single L4 GPU for standard operations.

However, should you opt for a larger quantization scale (upwards to no quantization), accommodating the increased memory and computational demands may necessitate scaling up to eight L4 GPUs to achieve optimal production performance. Consequently, it's advisable to adjust the number of shards to 8 in such scenarios to fully leverage the enhanced processing capacity and ensure that the deployment is scaled appropriately to handle the increased workload efficiently.

### Feature-specific to Model
*  Model: Mixtral8x7B-instruct-v0.1, a transformer-based architecture contained in a Mixture of experts with sparse gating model.
*   Attention Mechanisms:
    - Grouped-Query Attention (GQA): The GQA framework is an innovative approach to managing memory and computational resources more efficiently. By categorizing attention heads into groups, each sharing a common key and value projection, GQA facilitates three distinct configurations:
    - GQA-1, akin to MQA (Mixed Query Attention), focuses on enhancing the model's responsiveness and agility in handling queries.
    - GQA-H, reflective of the traditional Multi-Head Attention (MHA) mechanism, balances complexity with computational efficiency.
    - GQA-G, an intermediate form, optimizes both expressiveness and efficiency. This organization of query heads into groups minimizes memory overhead and enables precise control over performance, addressing challenges in scenarios requiring extensive context processing.
    - Sliding-Window Attention: This technique restricts the model's attention span to a localized set of positions around each token. By doing so, it significantly boosts the ability to grasp and leverage context-specific information, sharpening the model's comprehension and generation capabilities, especially for text requiring nuanced understanding of proximate relationships.

*   Tokenization:
    - Hybrid-fallback Tokenizer: Building on the byte-fallback BPE tokenizer's foundation, the Hybrid-fallback tokenizer introduces an adaptive mechanism that seamlessly switches between byte-level and subword encoding. This dual approach ensures comprehensive coverage across a diverse array of textual inputs, from highly frequent words to rare or out-of-vocabulary terms, guaranteeing no loss in textual fidelity.
*   Mixture of Experts (MoE)
Mixtral utilizes a unique component within its transformer architecture known as the MoE (Mixture-of-Experts) layer. This layer functions by intelligently directing input across a dynamically chosen subset of expert networks, each distinct in their training on various segments of data or specific tasks. By engaging this method, Mixtral is equipped to harness specialized knowledge and insights from these experts. This approach significantly enhances the model's capability for generating and analyzing text with greater accuracy and depth.

Set your region and project:

```bash
export REGION=us-central1
export PROJECT_ID=$(gcloud config get-value project)
```

#### GKE Cluster Creation:
```bash
gcloud container clusters create mixtral8x7-cluster-gke \
  --region=${REGION} \
  --node-locations=${REGION} \
  --project=${PROJECT_ID} \
  --machine-type=n2d-standard-8 \
  --no-enable-master-authorized-networks \
  --addons=HorizontalPodAutoscaling \
  --addons=HttpLoadBalancing \
  --addons=GcePersistentDiskCsiDriver \
  --addons=GcsFuseCsiDriver \
  --num-nodes=4 \
  --min-nodes=3 \
  --max-nodes=6 \
  --enable-ip-alias \
  --enable-image-streaming \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --enable-autoupgrade \
  --enable-autorepair \
  --network="projects/${PROJECT_ID}/global/networks/default" \
  --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default" \
  --tags=web,sftp \
  --labels=env=production,team=mixtral8x7 \
  --release-channel=regular

```

#### Node Pool with Single L4 GPU:
Create a node pool for deploying Mixtral 7B with quadpod deployment L4 GPU {4 x L4}:
```bash
gcloud container node-pools create mixtral-moe-gpu-pool \
  --cluster=mixtral8x7-cluster-gke  \
  --project=gke-aishared-dev \
  --machine-type=g2-standard-48 \
  --ephemeral-storage-local-ssd=count=4 \
  --accelerator=type=nvidia-l4,count=4 \
  --node-locations=us-west4-a \
  --enable-image-streaming \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=2 \
  --node-labels=accelerator=nvidia-gpu \
  --workload-metadata=GKE_METADATA
```

#### Hugging Face Authentication:
Obtain your Hugging Face token for model access: https://huggingface.co/settings/tokens
For Hugging Face authentication and to download the Mixtral8x7 instruct model:
```bash
export HF_TOKEN=<your-token>
kubectl create secret generic mixtral-demo --from-literal="HF_TOKEN=$HF_TOKEN"
```
Please use the given YAML file named mixtral-8x7b.yaml with the provided content: Mixtral8x7Bv0.1 instruct-deployment.

Deploy Mixtral8x7B with the following command:
```bash
kubectl apply -f mixtral8x7b.yaml
```

Assess the details of your deployment using the following command (Adjust if you utilized a different name in your YAML):
```bash
kubectl describe deployment mixtral8x7b -n default
```

Your output should resemble the following; please make sure the details are in accordance with your declarations and deployment needs: 

```bash
Name:                   mixtral8x7b
Namespace:              default
CreationTimestamp:      Fri, 22 Mar 2024 12:09:13 -0700
Labels:                 <none>
Annotations:            deployment.kubernetes.io/revision: 9
Selector:               app=mixtral8x7b
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=mixtral8x7b
  Containers:
   mixtral8x7b:
    Image:      us-docker.pkg.dev/deeplearning-platform-release/gcr.io/huggingface-text-generation-inference-cu124.2-3.ubuntu2204.py311
    Port:       8080/TCP
    Host Port:  0/TCP
    Limits:
      cpu:             5
      memory:          42Gi
      nvidia.com/gpu:  4
    Requests:
      cpu:             5
      memory:          42Gi
      nvidia.com/gpu:  4
    Environment:
      QUANTIZE:   bitsandbytes-nf4
      MODEL_ID:   mistralai/Mixtral-8x7B-Instruct-v0.1
      NUM_SHARD:  2
      PORT:       8080
    Mounts:
      /tmp from ephemeral-volume (rw)
      /dev/shm from dshm (rw)
  Volumes:
   dshm:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
   tmp:
    Type:          HostPath (bare host directory volume)
    Path:          /mnt/stateful_partition/kube-ephemeral-ssd/mixtral-data
    HostPathType:  
   ephemeral-volume:
    Type:          EphemeralVolume (an inline specification for a volume that gets created and deleted with the pod)
    StorageClass:  premium-rwo
    Volume:        
    Labels:            type=ephemeral
    Annotations:       <none>
    Capacity:      
    Access Modes:  
    VolumeMode:    Filesystem
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
NewReplicaSet:   mixtral8x7b-5c888947fd (1/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  43m   deployment-controller  Scaled up replica set mixtral8x7b-5c888947fd to 1
```

Test the deployment by forwarding the port and using curl to send a prompt:

```bash
kubectl port-forward deployment/mixtral8x7b 8080:8080
```

#### Check for deployment and retrieve Load-Balancer external exposed ip address:
List Services: First, list all services in the namespace (assuming default namespace as per your YAML) to make sure your service is up and running.

```bash
kubectl get svc --namespace=default
```

Attach correct labels to load balancer deployment:
```bash
kubectl label service mixtral8x7b-service LLM_deployment=true model_LoadBalancer=true Ingress_Point=true
```


#### Generate Load Balancer Details:
To describe all services of type Load Balancer in your Kubernetes cluster, you should be able to see the details of your mixtral-LB here and get the ingress as well as external ip. (The external exposed ip will be important for connecting it to external services).
```bash
kubectl get services --all-namespaces -o wide | grep LoadBalancer | while read -r namespace name type cluster_ip external_ip ports age; do echo "Describing service $name in namespace $namespace:"; kubectl describe service -n $namespace $name; done
```

Your Load Balancer details should resemble the following
Describing service mixtral8x7b-service in namespace default:

```bash
Name:                     mixtral8x7b-service
Namespace:                default
Labels:                   <none>
Annotations:              <none>
Selector:                 app=mixtral8x7b
Type:                     LoadBalancer
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.65.140.207
IPs:                      10.65.140.207
LoadBalancer Ingress:     34.16.133.177
Port:                     <unset>  80/TCP
TargetPort:               8080/TCP
NodePort:                 <unset>  30640/TCP
Endpoints:                10.92.1.10:8080
Session Affinity:         None
External Traffic Policy:  Cluster
Events:                   <none>

```

#### OPTIONAL: (If using HPA) Make sure HPA Horizontal Pod Autoscalar is working (Please see HPA documentation and preconfigurations needed):
Please make sure you have adjusted the yaml file appropriately.
```bash
# kubectl describe hpa mixtral-8x7b-hpa
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

This README provides a concise guide to deploying the Mixtral8x7B instruct v.01 model, listed above are key steps and adjustments needed for a general sample deployment. Ensure to replace placeholders and commands with the specific details of your GKE setup and Mixtral-v.01-instruct model deployment.
