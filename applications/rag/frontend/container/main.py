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
import logging as log
import google.cloud.logging as logging
import traceback
import uuid

from flask import Flask, render_template, request, jsonify, session
from rai import dlp_filter # Google's Cloud Data Loss Prevention (DLP) API. https://cloud.google.com/security/products/dlp
from rai import nlp_filter # https://cloud.google.com/natural-language/docs/moderating-text
from cloud_sql import cloud_sql
from rag_langchain.rag_chain import clear_chat_history, create_chain, take_chat_turn, engine
from datetime import datetime, timedelta, timezone

# Setup logging
logging_client = logging.Client()
logging_client.setup_logging()

# TODO: refactor the app startup code into a flask app factory
# TODO: include the chat history cache in the app lifecycle and ensure that it's threadsafe.
app = Flask(__name__, static_folder='static')
app.jinja_env.trim_blocks = True
app.jinja_env.lstrip_blocks = True
app.config['ENGINE'] = engine # force the connection pool to warm up eagerly

SESSION_TIMEOUT_MINUTES = 30
#TODO replace with real secret
SECRET_KEY = "TODO replace this with an actual secret that is stored and managed by kubernetes and added to the terraform configuration."
app.config['SECRET_KEY'] = SECRET_KEY

# Create llm chain
llm_chain = create_chain()

@app.route('/get_nlp_status', methods=['GET'])
def get_nlp_status():
    nlp_enabled = nlp_filter.is_nlp_api_enabled()
    return jsonify({"nlpEnabled": nlp_enabled})

@app.route('/get_dlp_status', methods=['GET'])
def get_dlp_status():
    dlp_enabled = dlp_filter.is_dlp_api_enabled()
    return jsonify({"dlpEnabled": dlp_enabled})

@app.route('/get_inspect_templates')
def get_inspect_templates():
    return jsonify(dlp_filter.list_inspect_templates_from_parent())

@app.route('/get_deidentify_templates')
def get_deidentify_templates():
    return jsonify(dlp_filter.list_deidentify_templates_from_parent())

@app.before_request
def check_new_session():
    if 'session_id' not in session:
        # instantiate a new session using a generated UUID
        session_id = str(uuid.uuid4())
        session['session_id'] = session_id

@app.before_request
def check_inactivity():
    # Inactivity cleanup
    if 'last_activity' in session:
        time_elapsed = datetime.now(timezone.utc) - session['last_activity'] 

        if time_elapsed > timedelta(minutes=SESSION_TIMEOUT_MINUTES):
            print("Session inactive: Cleaning up resources...")
            session_id = session['session_id']
            # TODO: implement garbage collection process for idle sessions that have timed out
            clear_chat_history(session_id)
            session.clear()

    # Always update the 'last_activity' data
    session['last_activity'] = datetime.now(timezone.utc) 

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/prompt', methods=['POST'])
def handlePrompt():
    # TODO on page refresh, load chat history into browser.
    session['last_activity'] = datetime.now(timezone.utc) 
    data = request.get_json()
    warnings = []

    if 'prompt' not in data:
        return 'missing required prompt', 400

    user_prompt = data['prompt']
    log.info(f"handle user prompt: {user_prompt}")

    try:
        response = {}
        result = take_chat_turn(llm_chain, session['session_id'], user_prompt)
        response['text'] = result

        # TODO: enable filtering in chain
        if 'nlpFilterLevel' in data:
            if nlp_filter.is_content_inappropriate(response['text'], data['nlpFilterLevel']):
                response['text'] = 'The response is deemed inappropriate for display.'
                return {'response': response}
        if 'inspectTemplate' in data and 'deidentifyTemplate' in data:
            inspect_template_path = data['inspectTemplate']
            deidentify_template_path = data['deidentifyTemplate']
            if inspect_template_path != "" and deidentify_template_path != "":
                # filter the output with inspect setting. Customer can pick any category from https://cloud.google.com/dlp/docs/concepts-infotypes
                response['text'] = dlp_filter.inspect_content(inspect_template_path, deidentify_template_path, response['text'])

        if warnings:
            response['warnings'] = warnings
        log.info(f"response: {response}")
        return {'response': response}
    except Exception as err:
        log.info(f"exception from llm: {err}")
        traceback.print_exc()
        error_traceback = traceback.format_exc()
        response = jsonify({
            "warnings": warnings,
            "error": "An error occurred",
            "errorMessage": f"Error: {err}\nTraceback:\n{error_traceback}"
        })
        response.status_code = 500
        return response


if __name__ == '__main__':
    # TODO using gunicorn to start the server results in the first request being really slow.
    # Sometimes, the worker thread has to restart due to an unknown error.
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
