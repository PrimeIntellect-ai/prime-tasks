[Bug]: Vertex AI does not respect JSON schema key ordering
### What happened?

Following up on #8864 and #9625, which added support for `anyOf` to Vertex AI schemas.

Vertex AI requires an explicit `propertyOrdering` to be set, whereas OpenAI by default respects the order of keys as they appear in the schema (despite JSON being formally unordered).

See the documentation [here](https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/control-generated-output#fields).

Note that python since version 3.7+ maintains order of insertion in dicts, hence `json.loads` maintains order of keys, so this should be easy to add.

## Steps to Reproduce

```
curl http://localhost:4200/v1/chat/completions \
-H "Content-Type: application/json" \
-d '{
  "model": "gemini-2.0-flash",
  "messages": [
    {
      "role": "user",
      "content": "Generate a test object"
    }
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "key-order-test",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "e": { "type": "string" },
          "b": { "type": "string" },
          "g": { "type": "string" },
          "a": { "type": "string" },
          "d": { "type": "string" },
          "h": { "type": "string" },
          "c": { "type": "string" },
          "f": { "type": "string" }
        },
        "required": ["e", "b", "g", "a", "d", "h", "c", "f"]
      }
    }
  }
}' | jq

# Returns (note the ordering in content is alphabetical, not like our schema):
# {
#   "id": "chatcmpl-c91ec5b7-65e3-4b33-afb5-38b26c7becd2",
#   "created": 1743906297,
#   "model": "gemini-2.0-flash-001",
#   "object": "chat.completion",
#   "system_fingerprint": null,
#   "choices": [
#     {
#       "finish_reason": "stop",
#       "index": 0,
#       "message": {
#         "content": "{\n\"a\": \"test_a\",\n\"b\": \"test_b\",\n\"c\": \"test_c\",\n\"d\": \"test_d\",\n\"e\": \"test_e\",\n\"f\": \"test_f\",\n\"g\": \"test_g\",\n\"h\": \"test_h\"\n}",
#         "role": "assistant",
#         "tool_calls": null,
#         "function_call": null
#       },
#       "logprobs": -0.014937561353047689
#     }
#   ],
#   "usage": {
#     "completion_tokens": 75,
#     "prompt_tokens": 20,
#     "total_tokens": 95,
#     "completion_tokens_details": null,
#     "prompt_tokens_details": {
#       "audio_tokens": null,
#       "cached_tokens": null
#     }
#   },
#   "vertex_ai_grounding_metadata": [],
#   "vertex_ai_safety_results": [],
#   "vertex_ai_citation_metadata": []
# }
```

```
curl http://localhost:4200/v1/chat/completions \
-H "Content-Type: application/json" \
-d '{
  "model": "gemini-2.0-flash",
  "messages": [
    {
      "role": "user",
      "content": "Generate a test object"
    }
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "key-order-test",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "e": { "type": "string" },
          "b": { "type": "string" },
          "g": { "type": "string" },
          "a": { "type": "string" },
          "d": { "type": "string" },
          "h": { "type": "string" },
          "c": { "type": "string" },
          "f": { "type": "string" }
        },
        "required": ["e", "b", "g", "a", "d", "h", "c", "f"],
        "propertyOrdering": ["e", "b", "g", "a", "d", "h", "c", "f"],
      }
    }
  }
}' | jq

# Returns (note that the output keys are ordered as in the schema now):
# {
#   "id": "chatcmpl-e278019d-962d-4159-82da-92c57cbaaaea",
#   "created": 1743906392,
#   "model": "gemini-2.0-flash-001",
#   "object": "chat.completion",
#   "system_fingerprint": null,
#   "choices": [
#     {
#       "finish_reason": "stop",
#       "index": 0,
#       "message": {
#         "content": "{\n  \"e\": \"test_e\",\n  \"b\": \"test_b\",\n  \"g\": \"test_g\",\n  \"a\": \"test_a\",\n  \"d\": \"test_d\",\n  \"h\": \"test_h\",\n  \"c\": \"test_c\",\n  \"f\": \"test_f\"\n}",
#         "role": "assistant",
#         "tool_calls": null,
#         "function_call": null
#       },
#       "logprobs": -0.0021315547357122584
#     }
#   ],
#   "usage": {
#     "completion_tokens": 83,
#     "prompt_tokens": 20,
#     "total_tokens": 103,
#     "completion_tokens_details": null,
#     "prompt_tokens_details": {
#       "audio_tokens": null,
#       "cached_tokens": null
#     }
#   },
#   "vertex_ai_grounding_metadata": [],
#   "vertex_ai_safety_results": [],
#   "vertex_ai_citation_metadata": []
# }
```

### Relevant log output

```shell

```

### Are you a ML Ops Team?

No

### What LiteLLM version are you on ?

v1.65.4-nightly

### Twitter / LinkedIn details

_No response_

### Additional contract requirements

- When a structured-output schema contains object properties without an explicit `propertyOrdering`, Vertex AI requests must retain those properties' insertion order, including object schemas nested inside arrays.
- An explicit `propertyOrdering` supplied for a schema must be preserved rather than replaced by an inferred ordering.
