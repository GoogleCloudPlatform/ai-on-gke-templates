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
import requests


def post_request(endpoint, body_params, headers):
    """
    Perform a POST request to a given endpoint with specified body parameters and headers.

    Args:
    endpoint (str): The URL endpoint for the POST request.
    body_params (dict): The body parameters to be sent in the POST request.
    headers (dict): The headers to be included in the POST request.

    Returns:
    dict: The response from the POST request.
    """
    try:
        response = requests.post(endpoint, json=body_params, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}
