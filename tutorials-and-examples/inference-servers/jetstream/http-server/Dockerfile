# Ubuntu:22.04
# Use Ubuntu 22.04 from Docker Hub.
# https://hub.docker.com/_/ubuntu/tags?page=1&name=22.04
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV JETSTREAM_VERSION=main

RUN apt -y update && apt install -y --no-install-recommends \
    ca-certificates \
    git \
    python3.10 \
    python3-pip

RUN update-alternatives --install \
    /usr/bin/python3 python3 /usr/bin/python3.10 1

RUN git clone https://github.com/google/JetStream.git && \
cd /JetStream && \
git checkout ${JETSTREAM_VERSION} && \
pip install -e .

RUN pip3 install uvicorn
RUN pip3 install fastapi
RUN pip3 install pydantic
ENV PYTHONDONTWRITEBYTECODE=1

COPY http_server.py /httpserver/
WORKDIR /httpserver

CMD ["uvicorn", "http_server:app", "--host=0.0.0.0", "--port=8000"]