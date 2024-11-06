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

import google.cloud.dlp

from . import retry

# Convert the project id into a full resource id.
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "NULL")
parent = f"projects/{GCP_PROJECT_ID}"

# Instantiate a dlp client.
dlp_client = google.cloud.dlp_v2.DlpServiceClient()

logging.basicConfig(
    level=logging.ERROR, format="%(asctime)s - %(levelname)s - %(message)s"
)


def is_dlp_api_enabled():
    if parent == "NULL":
        return False
    # Check if the DLP API is enabled
    try:
        dlp_client.list_info_types(
            request={"parent": "en-US"}, retry=retry.retry_policy
        )
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False


def list_inspect_templates_from_parent():
    try:
        # Initialize request argument(s)
        request = google.cloud.dlp_v2.ListInspectTemplatesRequest(
            parent=parent,
        )

        # Make the request
        page_result = dlp_client.list_inspect_templates(
            request=request, retry=retry.retry_policy
        )

        name_list = []
        # Handle the response
        for response in page_result:
            name_list.append(response.name)
        return name_list
    except Exception as e:
        logging.error(e)
        raise e


def get_inspect_templates_from_name(name):
    try:
        request = google.cloud.dlp_v2.GetInspectTemplateRequest(
            name=name,
        )

        return dlp_client.get_inspect_template(request=request)
    except Exception as e:
        logging.error(e)
        raise e


def list_deidentify_templates_from_parent():
    try:
        # Initialize request argument(s)
        request = google.cloud.dlp_v2.ListDeidentifyTemplatesRequest(
            parent=parent,
        )

        # Make the request
        page_result = dlp_client.list_deidentify_templates(request=request)

        name_list = []
        # Handle the response
        for response in page_result:
            name_list.append(response.name)
        return name_list

    except Exception as e:
        logging.error(e)
        raise e


def get_deidentify_templates_from_name(name):
    try:
        request = google.cloud.dlp_v2.GetDeidentifyTemplateRequest(
            name=name,
        )

        return dlp_client.get_deidentify_template(
            request=request, retry=retry.retry_policy
        )
    except Exception as e:
        logging.error(e)
        raise e


def inspect_content(inspect_template_path, deidentify_template_path, input):
    try:
        inspect_templates = get_inspect_templates_from_name(inspect_template_path)
        deidentify_template = get_deidentify_templates_from_name(
            deidentify_template_path
        )

        # Construct item
        item = {"value": input}

        # Call the API
        response = dlp_client.deidentify_content(
            request={
                "parent": parent,
                "deidentify_config": deidentify_template.deidentify_config,
                "inspect_config": inspect_templates.inspect_config,
                "item": item,
            },
            retry=retry.retry_policy,
        )

        # Print out the results.
        print(response.item.value)
        return response.item.value
    except Exception as e:
        logging.error(e)
        raise e
