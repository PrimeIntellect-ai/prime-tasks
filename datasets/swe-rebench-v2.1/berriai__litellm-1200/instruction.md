[Feature]:  acomplete see explicit args instead of *args, **kwargs on acomplete,
### The Feature

> would love to see explicit args instead of *args, **kwargs on acomplete, like you have in complete

### Motivation, pitch

everyone loves intellisense

### Twitter / LinkedIn details

_No response_

### Additional contract requirements

`litellm.acompletion` (defined in `litellm.main` and exported as `litellm.acompletion`) must expose the following parameters as explicit named parameters in its public signature, so that they are discoverable through introspection and IDE auto-completion:

`model`, `messages`, `functions`, `function_call`, `timeout`, `temperature`, `top_p`, `n`, `stream`, `stop`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `logit_bias`, `user`, `response_format`, `seed`, `tools`, `tool_choice`, `logprobs`, `top_logprobs`, `deployment_id`, `base_url`, `api_version`, `api_key`, `model_list`.

The generic positional catch-all `*args` must not be used to accept these arguments; each of them must be accepted as an explicit named parameter.
