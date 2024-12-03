import streamlit as st
from langchain import HuggingFaceHub
from langchain import PromptTemplate, LLMChain
import os
key = 'HUGGINGFACEHUB_API_TOKEN'
value = os.getenv(key)
os.environ['HUGGINGFACEHUB_API_TOKEN'] = value


# Set Hugging Face Hub API token
# Make sure to store your API token in the `apikey_hungingface.py` file
#os.environ["HUGGINGFACEHUB_API_TOKEN"] = apikey_hungingface

# Set up the language model using the Hugging Face Hub repository
repo_id = "tiiuae/falcon-7b-instruct"
llm = HuggingFaceHub(repo_id=repo_id, model_kwargs={"temperature": 0.3, "max_new_tokens": 2000})

# Set up the prompt template
template = """
You are an artificial intelligence assistant.
The assistant gives helpful, detailed, and polite answers to the user's question
Question: {question}\n\nAnswer: Let's think step by step."""
prompt = PromptTemplate(template=template, input_variables=["question"])
llm_chain = LLMChain(prompt=prompt, llm=llm)

# Create the Streamlit app
def main():
    st.title("FALCON LLM Question-Answer App")

    # Get user input
    question = st.text_input("Enter your question")

    # Generate the response
    if st.button("Get Answer"):
        with st.spinner("Generating Answer..."):
            response = llm_chain.run(question)
        st.success(response)

if __name__ == "__main__":
    main()
