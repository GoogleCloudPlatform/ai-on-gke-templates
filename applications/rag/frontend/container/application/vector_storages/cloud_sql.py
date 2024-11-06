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
import uuid
import logging

from typing import List, Optional, Iterable, Any

from langchain_core.vectorstores import VectorStore
from langchain_core.embeddings import Embeddings
from langchain_core.documents import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter

from langchain_google_cloud_sql_pg import PostgresVectorStore


VECTOR_EMBEDDINGS_TABLE_NAME = os.environ.get("EMBEDDINGS_TABLE_NAME", "")
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 10

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


class CloudSQLVectorStore(VectorStore):

    def __init__(self, embedding_provider, engine):
        self.vector_store = PostgresVectorStore.create_sync(
            engine=engine,
            embedding_service=embedding_provider,
            table_name=VECTOR_EMBEDDINGS_TABLE_NAME,
        )
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE, chunk_overlap=CHUNK_OVERLAP, length_function=len
        )
        self.embeddings_service = embedding_provider

    @classmethod
    def from_texts(
        cls,
        texts: List[str],
        embedding: Embeddings,
        metadatas: Optional[List[dict]] = None,
        **kwargs: Any,
    ):
        raise NotImplementedError

    def add_texts(
        self, texts: Iterable[str], metadatas: List[dict] | None = None, **kwargs: Any
    ) -> List[str]:
        try:
            splits = self.splitter.split_documents(texts)
            ids = [str(uuid.uuid4()) for _ in range(len(splits))]
            self.vector_store.add_documents(splits, ids)
        except Exception as err:
            logging.error(f"Error: {err}")
            raise Exception(f"Error adding texts: {err}")

    def similarity_search(
        self, query: dict, k: int = 4, **kwargs: Any
    ) -> List[Document]:
        try:
            query_input = query.get("input")
            query_vector = self.embeddings_service.embed_query(query_input)
            docs = self.vector_store.similarity_search_by_vector(query_vector, k=k)
            return docs

        except Exception as err:
            logging.error(f"Something happened: {err}")
            raise Exception(f"Error on similarity search: {err}")
