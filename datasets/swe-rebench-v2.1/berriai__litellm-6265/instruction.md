[Bug]: {"detail":{"error":"LLM Model List not loaded in"}}
### What happened?

I am using litellm==1.49.4 and I have updated ollama today

want to get details on the model which was started using litellm



I'm starting litellm like this:
```
$ litellm --model ollama/llama3.2:latest --drop_params
INFO:     Started server process [42848]
INFO:     Waiting for application startup.

#------------------------------------------------------------#
#                                                            #
#           'It would help me if you could add...'            #
#        https://github.com/BerriAI/litellm/issues/new        #
#                                                            #
#------------------------------------------------------------#

 Thank you for using LiteLLM! - Krrish & Ishaan



Give Feedback / Get Help: https://github.com/BerriAI/litellm/issues/new



#------------------------------------------------------------#
#                                                            #
#              'I don't like how this works...'               #
#        https://github.com/BerriAI/litellm/issues/new        #
#                                                            #
#------------------------------------------------------------#

 Thank you for using LiteLLM! - Krrish & Ishaan



Give Feedback / Get Help: https://github.com/BerriAI/litellm/issues/new


INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:4000 (Press CTRL+C to quit)
```

Then when I want to get model info, i get "detail":{"error":"LLM Model List not loaded in"}
```

curl -X GET "http://0.0.0.0:4000/model/info" --header 'Content-Type: application/json'
{"detail":{"error":"LLM Model List not loaded in"}}
```
And in Python:
```

response = requests.get("http://0.0.0.0:4000/model/info",
                        headers={"accept": "application/json"})
print(response.json())
```

returns:

```

{'detail': {'error': 'LLM Model List not loaded in'}}
```

On the server side: **INFO:     127.0.0.1:51828 - "GET /model/info HTTP/1.1" 500 Internal Server Error**

```
#------------------------------------------------------------#
#                                                            #
#           'I get frustrated when the product...'            #
#        https://github.com/BerriAI/litellm/issues/new        #
#                                                            #
#------------------------------------------------------------#

 Thank you for using LiteLLM! - Krrish & Ishaan



Give Feedback / Get Help: https://github.com/BerriAI/litellm/issues/new


INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:4000 (Press CTRL+C to quit)
INFO:     127.0.0.1:51828 - "GET /model/info HTTP/1.1" 500 Internal Server Error
```

### Relevant log output

_No response_

### Twitter / LinkedIn details

_No response_

### Additional contract requirements

When the proxy is started with a single model via the CLI (for example
`litellm --model ollama/llama3.2:latest`), `GET /model/info` must return model
details in a `{"data": ...}` response that includes the configured model
name, instead of raising the reported 500 `LLM Model List not loaded in` error.
