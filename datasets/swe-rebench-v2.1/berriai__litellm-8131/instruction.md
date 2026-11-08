[Bug]: Cannot pass provider-specific parameters to Bedrock Anthropic models
### What happened?

Passing the `top_k` parameter to an Anthropic model in the Bedrock platform throws this error:
```BadRequestError: litellm.BadRequestError: BedrockException - {"message":"The model returned the following errors: Malformed input request: #: extraneous key [inferenceConfig] is not permitted, please reformat your input and try again."}```

I think the issue is with the Bedrock Converse API, sometimes the additional parameters are passed in this way ([from the API docs](https://docs.aws.amazon.com/nova/latest/userguide/using-converse-api.html)):
```
additionalModelRequestFields = {
    "inferenceConfig": {
         "topK": 20
    }
}

model_response = client.converse(
    modelId="us.amazon.nova-lite-v1:0",
    messages=messages,
    system=system,
    inferenceConfig=inf_params,
    additionalModelRequestFields=additionalModelRequestFields
)
```

Sometimes it's passed without the `inferenceConfig` key, such as this example in the [API docs](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference-examples.html):
```
additional_model_fields = {"top_k": top_k}

    # Send the message.
    response = bedrock_client.converse(
        modelId=model_id,
        messages=messages,
        system=system_prompts,
        inferenceConfig=inference_config,
        additionalModelRequestFields=additional_model_fields
    )
```

I managed to fix the error for Anthropic by changing the litellm code [here](https://github.com/BerriAI/litellm/blob/fe60a38c8e43e908f44d8c668a5ba9fae1dca762/litellm/llms/bedrock/chat/converse_transformation.py#L381) to this:
```
[HIDDEN]
```
However if you do that, then it stops working for the Nova model. So I'm not sure what the solution is here!



### Relevant log output

_No response_

### Are you a ML Ops Team?

No

### What LiteLLM version are you on ?

1.58.2

### Twitter / LinkedIn details

_No response_

### Additional contract requirements

- For Bedrock Anthropic models, a `top_k` value passed to `litellm.completion` must be sent in the request body's `additionalModelRequestFields` as `{"top_k": <value>}`, not wrapped in an `inferenceConfig` key.
- For Bedrock Nova models, a `top_k` value passed to `litellm.completion` must be sent in `additionalModelRequestFields` as `{"inferenceConfig": {"topK": <value>}}`.
- For other Bedrock Converse models that do not support top-k, the request must not carry a top-k value in `additionalModelRequestFields`.
