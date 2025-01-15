FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

RUN apt-get update && \
    apt-get -y --no-install-recommends install python3-dev gcc python3-pip git && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    accelerate==1.1.1 bitsandbytes==0.45.0 \
    datasets==3.2.0 transformers==4.46.3 \
    peft==0.13.2 trl==0.12.2 torch==2.5.1 torchvision==0.20.1 \
    mlflow==2.19.0 google-cloud-storage==2.19.0

COPY finetune.py /finetune.py

ENV PYTHONUNBUFFERED 1

CMD python3 /finetune.py --device cuda
