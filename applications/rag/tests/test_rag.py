import json
import sys
import requests

def test_prompts(prompt_url):
    try:
        testcases = [
            {
                "prompt": "List the cast of Squid Game",
            },
            {
                "prompt": "When was Squid Game released?",
            },
            {
                "prompt": "What is the rating of Squid Game?",
            },
            {
                "prompt": "List the cast of Avatar: The Last Airbender",
            },
            {
                "prompt": "When was Avatar: The Last Airbender added on Netflix?",
            },
            {
                "prompt": "What is the rating of Avatar: The Last Airbender?",
            },
        ]

        for testcase in testcases:
            prompt = testcase["prompt"]

            print(f"Testing prompt: {prompt}")
            data = {"prompt": prompt}
            json_payload = json.dumps(data)

            headers = {'Content-Type': 'application/json'}
            response = requests.post(prompt_url, data=json_payload, headers=headers)
            response.raise_for_status()

            response = response.json()
            print(response)
            text = response['response'].get('text')

            print(f"Reply: {text}")

            assert response != None, f"Not response found: {response}"
            assert text != None, f"Not text"
    except Exception as err:
            print(err)
            raise err

def test_prompts_nlp(prompt_url):
    try:
        testcases = [
            {
                "prompt": "List the cast of Squid Game",
                "nlpFilterLevel": "0",
            },
            {
                "prompt": "Which movie has a building that blows up?",
                "nlpFilterLevel": "0",
            },
            {
                "prompt": "Which movie has a building that blows up?",
                "nlpFilterLevel": "50",
            },
            {
                "prompt": "List the cast of Squid Game",
                "nlpFilterLevel": "100",
            }
        ]

        for testcase in testcases:
            prompt = testcase["prompt"]
            nlpFilterLevel = testcase["nlpFilterLevel"]

            print(f"Testing prompt: {prompt}")
            data = {"prompt": prompt, "nlpFilterLevel": nlpFilterLevel}
            json_payload = json.dumps(data)

            headers = {'Content-Type': 'application/json'}
            response = requests.post(prompt_url, data=json_payload, headers=headers)
            response.raise_for_status()

            response = response.json()

            text = response['response']['text']


            print(f"Reply: {text}")

            assert response != None, f"Not response found: {response}"
            assert text != None, f"Not text"
    except Exception as err:
            print(err)
            raise err

def test_prompts_dlp(prompt_url):
    try:
        testcases = [
            {
                "prompt": "who worked with Robert De Niro and name one film they collaborated?",
                "inspectTemplate": "projects/gke-ai-eco-dev/locations/global/inspectTemplates/DO-NOT-DELETE-e2e-test-inspect-template",
                "deidentifyTemplate": "projects/gke-ai-eco-dev/locations/global/deidentifyTemplates/DO-NOT-DELETE-e2e-test-de-identify-template",
            },
        ]

        for testcase in testcases:
            prompt = testcase["prompt"]
            inspectTemplate = testcase["inspectTemplate"]
            deidentifyTemplate = testcase["deidentifyTemplate"]

            print(f"Testing prompt: {prompt}")
            data = {"prompt": prompt, "inspectTemplate": inspectTemplate, "deidentifyTemplate": deidentifyTemplate}
            json_payload = json.dumps(data)

            headers = {'Content-Type': 'application/json'}
            response = requests.post(prompt_url, data=json_payload, headers=headers)
            response.raise_for_status()

            response = response.json()
            text = response['response']['text']


            print(f"Reply: {text}")

            assert response != None, f"Not response found: {response}"
            assert text != None, f"Not text"
    except Exception as err:
            print(err)
            raise err

if __name__ == "__main__":
    prompt_url = sys.argv[1]
    test_prompts(prompt_url)
    test_prompts_nlp(prompt_url)
    test_prompts_dlp(prompt_url)