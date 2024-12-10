# Ubuntu:22.04
# Use Ubuntu 22.04 from Docker Hub.
# https://hub.docker.com/_/ubuntu/tags?page=1&name=22.04
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTORCH_JETSTREAM_VERSION=main

RUN apt -y update && apt install -y --no-install-recommends \
    ca-certificates \
    git \
    python3.10 \
    python3-pip

RUN python3 -m pip install --upgrade pip

RUN update-alternatives --install \
    /usr/bin/python3 python3 /usr/bin/python3.10 1

RUN git clone https://github.com/AI-Hypercomputer/jetstream-pytorch.git && \
git clone https://github.com/AI-Hypercomputer/JetStream.git

RUN cd /jetstream-pytorch && \
git checkout ${PYTORCH_JETSTREAM_VERSION} && \
bash install_everything.sh

RUN cd /JetStream && \
pip install -e .

COPY jetstream_pytorch_server_entrypoint.sh /usr/bin/

RUN chmod +x /usr/bin/jetstream_pytorch_server_entrypoint.sh

ENTRYPOINT ["/usr/bin/jetstream_pytorch_server_entrypoint.sh"]