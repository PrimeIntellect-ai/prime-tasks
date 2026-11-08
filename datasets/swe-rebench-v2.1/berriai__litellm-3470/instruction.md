[Bug]: Embedding Function on Ollama Seems not Working
### What happened?


Embedding functionality seems not working for Ollama. I have `nomic-embed-text` installed and tested using Ollama Python library..

`response = embedding(model='ollama/nomic-embed-text',
                     input=["good morning from litellm"],
                     api_base="http://localhost:11434")
print(response)`


I don't know if I am using embedding function incorrectly or there is another issue (lack of Ollama support for embeddings, bug etc.)


### Relevant log output

```shell
File "/home/****/codes/python/experiment-litellm/main.py", line 41, in <module>
    response = embedding(model='ollama/nomic-embed-text',
  File "/home/****/miniconda3/envs/experiment-litellm/lib/python3.8/site-packages/litellm/utils.py", line 3129, in wrapper
    raise e
  File "/home/****/miniconda3/envs/experiment-litellm/lib/python3.8/site-packages/litellm/utils.py", line 3072, in wrapper
    result._response_ms = (
AttributeError: 'NoneType' object has no attribute '_response_ms'
```


### Twitter / LinkedIn details

_No response_
