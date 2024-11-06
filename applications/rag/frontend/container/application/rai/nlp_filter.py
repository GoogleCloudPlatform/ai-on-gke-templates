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

import google.cloud.language_v1 as language

from . import retry

# Convert the project id into a full resource id.
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "NULL")
parent = f"projects/{GCP_PROJECT_ID}"

# Instantiate a nlp client.
nature_language_client = language.LanguageServiceClient()

logging.basicConfig(
    level=logging.ERROR, format="%(asctime)s - %(levelname)s - %(message)s"
)


def is_nlp_api_enabled():
    if parent == "NULL":
        return False
    # Check if the DLP API is enabled
    try:
        sum_moderation_confidences("test")
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False


def sum_moderation_confidences(text):
    try:
        document = language.types.Document(
            content=text, type_=language.types.Document.Type.PLAIN_TEXT
        )

        request = language.ModerateTextRequest(
            document=document,
        )
        # Detects the sentiment of the text
        response = nature_language_client.moderate_text(
            request=request, retry=retry.retry_policy
        )
        print(f"get response: {response}")
        # Parse response and sum the confidences of moderation, the categories are from https://cloud.google.com/natural-language/docs/moderating-text
        largest_confidence = 0.0
        excluding_names = ["Health", "Politics", "Finance", "Legal"]
        for category in response.moderation_categories:
            if category.name in excluding_names:
                continue
            if category.confidence > largest_confidence:
                largest_confidence = category.confidence

        print(f"largest confidence is: {largest_confidence}")
        return int(largest_confidence * 100)
    except Exception as e:
        logging.error(e)
        raise e


def is_content_inappropriate(text, nlp_filter_level):
    try:
        return sum_moderation_confidences(text) > (100 - int(nlp_filter_level))
    except Exception as e:
        logging.error(e)
        raise e
