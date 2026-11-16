[Bug]: SSE chunks that come from OpenRouter in a stream lose their OpenRouter ID
### What happened?

When using OpenRouter with stream=true the ids are getting generated inside litellm and not getting picked up from OpenRouter generated gen IDs.

I added in the logs the output of a small test script I have that prints the chunks as they come, I also created a fork of the main repo to add a log in the transformation.py of the openrouter right before we return the sse chunk to see what the id is equal in there (formatted as "CHUNK_ID = " + chunk["id"]). As you can see its generating a new one instead of using the one it gets.

### Relevant log output

```shell
Chunk 40 details:
  ID: chatcmpl-27788257-1cd5-489a-81f7-ad3acdc77f47
  Object: chat.completion.chunk
  Created: 1747832344
  Model: openai/gpt-3.5-turbo
  Finish reason: None
  Has usage: False

CHUNK_ID = gen-1747832343-r1R4jd69FBv5lkWPp9e6

Chunk 41 details:
  ID: chatcmpl-27788257-1cd5-489a-81f7-ad3acdc77f47
  Object: chat.completion.chunk
  Created: 1747832344
  Model: openai/gpt-3.5-turbo
  Finish reason: stop
  Has usage: False
```

### Are you a ML Ops Team?

No

### What LiteLLM version are you on ?

v1.70.3

### Twitter / LinkedIn details

https://www.linkedin.com/in/dagokogos/

### Additional contract requirements

- `CustomStreamWrapper` (importable from `litellm.litellm_core_utils.streaming_handler`) exposes a public method `set_model_id(self, id: str, model_response: ModelResponseStream) -> ModelResponseStream` and a public attribute `response_id`. The method records the response id and returns `model_response` with its `id` field set to the recorded response id:
  - A non-empty `id` string becomes the recorded `response_id`.
  - An empty or whitespace-only `id` leaves an already-recorded `response_id` unchanged and applies it to `model_response.id`.
  - The returned `model_response.id` equals the recorded `response_id`.
