# Tutorial: Serving Llama 2 70b on GKE L4 GPUs
Learn how to serve Llama 2 70b chat model on GKE using just 2 x L4 GPUs. For
this post the text-generation-inference project is used for serving.

### Prerequisites
*   A terminal with `kubectl` and `gcloud` installed. Cloud Shell works great!
*   L4 GPUs quota to be able to run additional 2 L4 GPUs
*   Request access to Meta Llama models by submitting the [request access form](https://ai.meta.com/resources/models-and-libraries/llama-downloads/)
*   Agree to the Llama 2 terms on the [Llama 2 70B Chat HF](https://huggingface.co/meta-llama/Llama-2-70b-chat-hf) model in HuggingFace

Choose your region and set your project:
```bash
export REGION=us-central1
export PROJECT_ID=$(gcloud config get project)
```

Create a GKE cluster:
```bash
gcloud container clusters create l4-demo --location ${REGION} \
  --workload-pool ${PROJECT_ID}.svc.id.goog \
  --enable-image-streaming --enable-shielded-nodes \
  --shielded-secure-boot --shielded-integrity-monitoring \
  --enable-ip-alias \
  --node-locations=$REGION-a \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --addons GcsFuseCsiDriver   \
  --no-enable-master-authorized-networks \
  --machine-type n2d-standard-4 \
  --num-nodes 1 --min-nodes 1 --max-nodes 5 \
  --ephemeral-storage-local-ssd=count=2 \
  --enable-ip-alias
```

Create a nodepool where each VM has 2 x L4 GPU:
```bash
gcloud container node-pools create g2-standard-24 --cluster l4-demo \
  --accelerator type=nvidia-l4,count=2,gpu-driver-version=latest \
  --machine-type g2-standard-24 \
  --ephemeral-storage-local-ssd=count=2 \
  --enable-autoscaling --enable-image-streaming \
  --num-nodes=0 --min-nodes=0 --max-nodes=3 \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --node-locations $REGION-a,$REGION-b --region $REGION --spot
```

Hugging Face requires authentication to download the [Llama-2-70b-chat-hf](https://huggingface.co/meta-llama/Llama-2-70b-chat-hf) model, which means an access token is required to download the model.

You can get your access token from [huggingface.com > Settings > Access Tokens](https://huggingface.co/settings/tokens). Afterwards, set your HuggingFace token as an environment variable:
```bash
export HF_TOKEN=<paste-your-own-token>
```

Create a Secret to store your HuggingFace token which will be used by the K8s job:
```bash
kubectl create secret generic l4-demo --from-literal="HF_TOKEN=$HF_TOKEN"
```

Create a file named `text-generation-interface.yaml` with the following content:

[embedmd]:# (text-generation-interface.yaml)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-2-70b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-2-70b
  template:
    metadata:
      labels:
        app: llama-2-70b
    spec:
      containers:
      - name: llama-2-70b
        image: us-docker.pkg.dev/deeplearning-platform-release/gcr.io/huggingface-text-generation-inference-cu124.2-3.ubuntu2204.py311
        resources:
          limits:
            nvidia.com/gpu: 2
        env:
        - name: MODEL_ID
          value: meta-llama/Llama-2-70b-chat-hf
        - name: NUM_SHARD
          value: "2"
        - name: PORT 
          value: "8080"
        - name: QUANTIZE
          value: bitsandbytes-nf4
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: l4-demo
              key: HF_TOKEN
        volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /tmp
            name: tmp
      volumes:
         - name: dshm
           emptyDir:
              medium: Memory
         - name: tmp
           hostPath:
            path: /mnt/stateful_partition/kube-ephemeral-ssd/llama-data
      nodeSelector:
        cloud.google.com/gke-accelerator: nvidia-l4
```

Create the deployment for serving:
```bash
kubectl apply -f text-generation-interface.yaml
```

Inside the YAML file the following settings are used:
- `NUM_SHARD`, this has to be set to 2 because 2 x NVIDIA L4 GPUs are used. In our testing without setting this value it will only use a single GPU.
- `QUANTIZE` is set to `nf4` which means that the model is loaded in 4 bit instead of 32 bits. This allows us to reduce the amount of GPU memory needed and improves the inference speed, however it can also decrease the model accuracy. If you change this you might need additional GPUs

Visit the [text-generation-inference docs](https://github.com/huggingface/text-generation-inference/blob/v1.1.0/docs/source/basic_tutorials/launcher.md) for more details about these settings.

How do you know how many GPUs you need?  
That depends on the value of `QUANTIZE`, in our case it is set to `bitsandbytes-nf4`,
which means that the model will be loaded in 4 bits. So a 70 billion parameter model would
require a minimum of 70 billion * 4 bits = 35 GB of GPU memory, lets say there is 5GB of overhead, which takes the minimum to 40GB. The L4 GPU has 24GB of GPU memory, so a single
L4 GPU wouldn't have enough memory, however 2 x 24 = 48GB GPU memory, so using 2 x L4 GPU
is sufficient to run Llama 2 70B on L4 GPUs.


Check the logs and make sure there are no errors:
```bash
kubectl logs -l app=llama-2-70b
```

It's time to test it out by sending it some prompts.
Setup port forwarding to the inferencing server:
```bash
kubectl port-forward deployment/llama-2-70b 8080:8080
```

Now you can chat with your model through a simple curl:
```bash
curl 127.0.0.1:8080/generate -X POST \
    -H 'Content-Type: application/json' \
    --data-binary @- <<EOF
{
    "inputs": "[INST] <<SYS>>\nYou are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe.  Your answers should not include any harmful, unethical, racist, sexist, toxic, dangerous, or illegal content. Please ensure that your responses are socially unbiased and positive in nature. If a question does not make any sense, or is not factually coherent, explain why instead of answering something not correct. If you don't know the answer to a question, please don't share false information.\n<</SYS>>\nHow to deploy a container on K8s?[/INST]",
    "parameters": {"max_new_tokens": 400}
}
EOF
```

There are also API docs available at [http://localhost:8080/docs](http://localhost:8080/docs).
