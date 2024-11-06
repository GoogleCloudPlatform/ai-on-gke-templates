# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import logging

import google.cloud.logging as gcloud_logging

from google.cloud.sql.connector import IPTypes

from langchain_google_cloud_sql_pg import PostgresEngine

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
gcloud_logging_client = gcloud_logging.Client()
gcloud_logging_client.setup_logging()


ENVIRONMENT = os.environ.get("ENVIRONMENT")

GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
GCP_CLOUD_SQL_REGION = os.environ.get("CLOUDSQL_INSTANCE_REGION")
GCP_CLOUD_SQL_INSTANCE = os.environ.get("CLOUDSQL_INSTANCE")

DB_NAME = os.environ.get("DB_NAME", "pgvector-database")
VECTOR_EMBEDDINGS_TABLE_NAME = os.environ.get("EMBEDDINGS_TABLE_NAME", "")
CHAT_HISTORY_TABLE_NAME = os.environ.get("CHAT_HISTORY_TABLE_NAME", "message_store")

VECTOR_DIMENSION = os.environ.get("VECTOR_DIMENSION", 384)

try:
    db_username_file = open("/etc/secret-volume/username", "r")
    DB_USER = db_username_file.read()
    db_username_file.close()

    db_password_file = open("/etc/secret-volume/password", "r")
    DB_PASS = db_password_file.read()
    db_password_file.close()
except:
    DB_USER = os.environ.get("DB_USERNAME", "postgres")
    DB_PASS = os.environ.get("DB_PASS", "postgres")


def create_sync_postgres_engine():
    engine = PostgresEngine.from_instance(
        project_id=GCP_PROJECT_ID,
        region=GCP_CLOUD_SQL_REGION,
        instance=GCP_CLOUD_SQL_INSTANCE,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        ip_type=IPTypes.PUBLIC if ENVIRONMENT == "development" else IPTypes.PRIVATE,
    )
    try:
        engine.init_vectorstore_table(
            VECTOR_EMBEDDINGS_TABLE_NAME,
            vector_size=VECTOR_DIMENSION,
            overwrite_existing=False,
        )
    except Exception as err:
        logging.error(f"Error: {err}")

    try:
        engine.init_chat_history_table(table_name=CHAT_HISTORY_TABLE_NAME)

    except Exception as err:
        logging.error(f"Error: {err}")
    return engine
