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

import uuid
import traceback
import logging as log

import google.cloud.logging as logging

from flask import render_template, request, jsonify, session, redirect, url_for
from datetime import datetime, timedelta, timezone

from application import create_app
from application.rai import (
    dlp_filter,
)  # Google's Cloud Data Loss Prevention (DLP) API. https://cloud.google.com/security/products/dlp
from application.rai import (
    nlp_filter,
)  # https://cloud.google.com/natural-language/docs/moderating-text

from application.rag_langchain.rag_chain import (
    clear_chat_history,
    create_chain,
    take_chat_turn,
    get_chat_history,
)

log.basicConfig(level=log.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

SESSION_TIMEOUT_MINUTES = 20

# Setup logging
logging_client = logging.Client()
logging_client.setup_logging()

app = create_app()

# Create llm chain
llm_chain = create_chain()


@app.before_request
def check_new_session():
    if "session_id" not in session:
        # instantiate a new session using a generated UUID
        session_id = str(uuid.uuid4())
        session["session_id"] = session_id


@app.before_request
def check_inactivity():
    # Inactivity cleanup
    if "last_activity" in session:
        time_elapsed = datetime.now(timezone.utc) - session["last_activity"]

        if time_elapsed > timedelta(minutes=SESSION_TIMEOUT_MINUTES):
            print("Session inactive: Cleaning up resources...")
            session_id = session["session_id"]
            # TODO: implement garbage collection process for idle sessions that have timed out
            clear_chat_history(session_id)
            session.clear()

    # Always update the 'last_activity' data
    session["last_activity"] = datetime.now(timezone.utc)


@app.route("/get_nlp_status", methods=["GET"])
def get_nlp_status():
    nlp_enabled = nlp_filter.is_nlp_api_enabled()
    return jsonify({"nlpEnabled": nlp_enabled})


@app.route("/get_dlp_status", methods=["GET"])
def get_dlp_status():
    dlp_enabled = dlp_filter.is_dlp_api_enabled()
    return jsonify({"dlpEnabled": dlp_enabled})


@app.route("/get_inspect_templates")
def get_inspect_templates():
    return jsonify(dlp_filter.list_inspect_templates_from_parent())


@app.route("/get_deidentify_templates")
def get_deidentify_templates():
    return jsonify(dlp_filter.list_deidentify_templates_from_parent())


@app.route("/get_chat_history", methods=["GET"])
def get_chat_history_endpoint():
    try:
        session_id = session.get("session_id")
        if not session_id:
            return redirect(url_for("index"))

        history = get_chat_history(session_id)

        messages_response = []
        for message in history.messages:
            data = {"prompt": message.type, "message": message.content}
            messages_response.append(data)

        response = jsonify({"history_messages": messages_response})
        response.status_code = 200

        return response

    except Exception as err:
        log.info(f"exception from llm: {err}")
        traceback.print_exc()
        error_traceback = traceback.format_exc()
        response = jsonify(
            {
                "error": "An error occurred",
                "errorMessage": f"Error: {err}\nTraceback:\n{error_traceback}",
            }
        )
        response.status_code = 500
        return response


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/prompt", methods=["POST"])
def handlePrompt():
    # TODO on page refresh, load chat history into browser.
    session["last_activity"] = datetime.now(timezone.utc)
    data = request.get_json()
    warnings = []

    if "prompt" not in data:
        return "missing required prompt", 400

    user_prompt = data["prompt"]
    log.info(f"handle user prompt: {user_prompt}")

    try:
        session_id = session.get("session_id")
        if not session_id:
            return redirect(url_for("index"))
        response = {}
        result = take_chat_turn(llm_chain, session_id, user_prompt)
        response["text"] = result

        # TODO: enable filtering in chain
        if "nlpFilterLevel" in data:
            if nlp_filter.is_content_inappropriate(
                response["text"], data["nlpFilterLevel"]
            ):
                response["text"] = "The response is deemed inappropriate for display."
                return {"response": response}
        if "inspectTemplate" in data and "deidentifyTemplate" in data:
            inspect_template_path = data["inspectTemplate"]
            deidentify_template_path = data["deidentifyTemplate"]
            if inspect_template_path != "" and deidentify_template_path != "":
                # filter the output with inspect setting. Customer can pick any category from https://cloud.google.com/dlp/docs/concepts-infotypes
                response["text"] = dlp_filter.inspect_content(
                    inspect_template_path, deidentify_template_path, response["text"]
                )

        if warnings:
            response["warnings"] = warnings
        return {"response": response}

    except Exception as err:
        log.info(f"exception from llm: {err}")
        traceback.print_exc()
        error_traceback = traceback.format_exc()
        response = jsonify(
            {
                "warnings": warnings,
                "error": "An error occurred",
                "errorMessage": f"Error: {err}\nTraceback:\n{error_traceback}",
            }
        )
        response.status_code = 500
        return response
