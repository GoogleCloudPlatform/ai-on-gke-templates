FROM python:3.10-slim-bullseye

ENV HOST=0.0.0.0

ENV LISTEN_PORT 8080

ENV HUGGINGFACEHUB_API_TOKEN="hf_fugging_face_token_here"

EXPOSE 8080

RUN apt-get update && apt-get install -y git

COPY ./requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /app/requirements.txt

WORKDIR app/

COPY ./main.py /app/main.py
#COPY ./langchain_helper.py /app/langchain_helper.py
#COPY ./secret_key.py /app/secret_key.py

CMD ["streamlit", "run", "main.py", "--server.port", "8080"]
