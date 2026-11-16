[Bug]: Streaming Anthropic tools doesn't map the tool index
# What happened?

You can't currently use streaming + function calls with anthropic.

When using litellm@main  as a proxy with `openai-node@v4.55.7` (and I think most if not all previous versions for both), to use tools with streaming, I'm getting this error message.

```
OpenAIError: Cannot read properties of undefined (reading 'type')
    at ChatCompletionStream._EventStream_handleError (/work/server/node_modules/openai/src/lib/EventStream.ts:159:40)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5) {
  cause: TypeError: Cannot read properties of undefined (reading 'type')
      at ChatCompletionStream._addMessage (/work/server/node_modules/openai/src/lib/AbstractChatCompletionRunner.ts:70:25)
      at ChatCompletionStream._addChatCompletion (/work/server/node_modules/openai/src/lib/AbstractChatCompletionRunner.ts:48:23)
      at ChatCompletionStream._createChatCompletion (/work/server/node_modules/openai/src/lib/ChatCompletionStream.ts:392:17)
      at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
      at ChatCompletionStream._runChatCompletion (/work/server/node_modules/openai/src/lib/AbstractChatCompletionRunner.ts:264:12)
}
```

The cause of this is `_addMessage`, it loops through all of the `message.tool_calls` and tries to do `tool_call.type` when `tool_call` is undefined. [AbstractChatCompletionRunner.ts#L69](https://github.com/openai/openai-node/blob/master/src/lib/AbstractChatCompletionRunner.ts#L69)

```typescript
else if (isAssistantMessage(message) && message.tool_calls) {
  for (const tool_call of message.tool_calls) {
    if (tool_call.type === 'function') {
      this._emit('functionCall', tool_call.function);
    }
  }
}
```

This is because `message.tool_calls` containing an empty element before the actual tool call.
For example this is what `message.tool_calls` looks like for me:

```
[
  <1 empty item>,
  {
    id: 'toolu_redacted',
    type: 'function',
    function: { name: 'get_unsplash_image', arguments: '{"query": "cute cats"}' }
  }
]
```



This happens is because openai and anthropic index their tools differently when streaming.

<details>

<summary>OpenAI Request</summary>

```json
{
  "model": "gpt-4o",
  "messages": [
    {
      "role": "user",
      "content": "Write a sentence about a bird, then What's the weather like in Boston and LA today?"
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_current_weather",
        "description": "Get the current weather in a given location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "The city and state, e.g. San Francisco, CA"
            },
            "unit": {
              "type": "string",
              "enum": ["celsius", "fahrenheit"]
            }
          },
          "required": ["location"]
        }
      }
    }
  ],
  "temperature": 0,
  "tool_choice": "auto",
  "stream": true
}
```

</details>

<details>

<summary>OpenAI Response</summary>

```
data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"role":"assistant","content":"","refusal":null},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":"The"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" vibrant"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" par"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":"rot"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" perched"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" on"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" the"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" tree"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" branch"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":","},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" its"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" feathers"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" shimmering"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" in"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" the"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" sunlight"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":".\n\n"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":"Let's"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" find"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" out"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" the"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" weather"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" in"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" Boston"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":","},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" MA"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" and"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" Los"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" Angeles"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":","},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" CA"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":" today"},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"content":"."},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_9oOUGn7XVM1S9AdJeglwUv1Z","type":"function","function":{"name":"get_current_weather","arguments":""}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"lo"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"catio"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"n\": \"B"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"osto"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"n, MA"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_J3BjbPf0uLzgzcSPrUc9Bnn1","type":"function","function":{"name":"get_current_weather","arguments":""}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\"lo"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"catio"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"n\": \"L"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"os A"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"ngele"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"s, CA\""}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"}"}}]},"logprobs":null,"finish_reason":null}]}

data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"tool_calls"}]}

data: [DONE]


```

</details>



Anthropic indexes all of think chunks on their own. So if there's text before it does the function call then the tools will start at index 1. [Because they usually use chain of thought, there will almost always be preceding text.](https://docs.anthropic.com/en/docs/build-with-claude/tool-use#chain-of-thought)

They can however start at index 0 if you ask it to.

Examples:


<details>

<summary>Anthropic Tool Request </summary>

```json
{
  "model": "claude-3-5-sonnet-20240620",
  "max_tokens": 1000,
  "messages": [
    {
      "role": "user",
      "content": "What's the weather like in Boston and LA today?. "
    }
  ],
  "tools": [
  {
    "name": "get_current_weather",
    "description": "Get the current weather in a given location",
    "input_schema": {
      "type": "object",
      "properties": {
        "location": {
          "type": "string",
          "description": "The city and state, e.g. San Francisco, CA"
        }
      },
      "required": ["location"]
    }
  }
],
  "temperature": 0,
  "stream": true
}
```

</details>

<details>

<summary>Anthropic Tool Response</summary>

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_redacted","type":"message","role":"assistant","model":"claude-3-5-sonnet-20240620","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":390,"output_tokens":1}}       }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""} }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"To"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" answer"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" your question about the weather"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" in Boston and Los"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" Angeles today, I'll"} }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" need to"}        }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" use"} }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" the"}             }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" get_current_weather"}        }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" function"}      }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" for"}      }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" both"}      }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" cities"}          }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":". Let"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" me fetch"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" that"}              }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" information"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" for"}      }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" you."}               }

event: content_block_stop
data: {"type":"content_block_stop","index":0             }

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01SzvAdMUT45UdVL85Hfk5JG","name":"get_current_weather","input":{}}         }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}   }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"locatio"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"n\": \"B"}          }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"oston, "}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"MA\"}"}      }

event: content_block_stop
data: {"type":"content_block_stop","index":1       }

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01VhASVc7tJyvedfL9YtpGtD","name":"get_current_weather","input":{}}             }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":""}      }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"lo"}              }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"catio"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"n\": \"Lo"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"s An"}     }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"gel"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"es"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":", CA\"}"}    }

event: content_block_stop
data: {"type":"content_block_stop","index":2             }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":137}     }

event: message_stop
data: {"type":"message_stop" }


```

</details>


<details>

<summary>Anthropic Tool Request at index 0</summary>

```json
{
  "model": "claude-3-5-sonnet-20240620",
  "max_tokens": 1000,
  "messages": [
    {
      "role": "user",
      "content": "What's the weather like in Boston and LA today?.  Do not say 'sure I can do that', or 'To provide the weather', or any chain of thought, or anything before the temperature. Only output the temperatures."
    }
  ],
  "tools": [
  {
    "name": "get_current_weather",
    "description": "Get the current weather in a given location",
    "input_schema": {
      "type": "object",
      "properties": {
        "location": {
          "type": "string",
          "description": "The city and state, e.g. San Francisco, CA"
        }
      },
      "required": ["location"]
    }
  }
],
  "temperature": 0,
  "stream": true
}
```

</details>

<details>

<summary>Anthropic Tool Response at index 0</summary>

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_redacted","type":"message","role":"assistant","model":"claude-3-5-sonnet-20240620","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":425,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01AGH43t4trjCvgKdaAaHmBu","name":"get_current_weather","input":{}}   }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}        }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"loc"}           }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ation\": "}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"Bos"}       }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ton, MA\"}"}               }

event: content_block_stop
data: {"type":"content_block_stop","index":0             }

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01KRsTyAGGq6N1ZJBqbhHSan","name":"get_current_weather","input":{}}  }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"locatio"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"n\": \"Los"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" Ang"}          }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"eles,"}             }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" CA\"}"}      }

event: content_block_stop
data: {"type":"content_block_stop","index":1       }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":98}    }

event: message_stop
data: {"type":"message_stop"           }

```

</details>

## Why there is a blank element

The reason why this happens is because Anthropic assigns indexes to chunk sequentially, starting with the initial text chunk. OpenAI gives tools their own index, starting at 0 with the first tool, regardless of any proceeding text.

I assume the openai library is assigning the tools to an array based on their given value, which for anthropic the tools will usually start with index 1, leaving index 0 unassigned.


```
# OpenAI:

... other messages
data: {"id":"chatcmpl-redacted","object":"chat.completion.chunk","created":1723736362,"model":"gpt-4o-2024-05-13","system_fingerprint":"fp_redacted","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_9oOUGn7XVM1S9AdJeglwUv1Z","type":"function","function":{"name":"get_current_weather","arguments":""}}]},"logprobs":null,"finish_reason":null}]}

# Anthropic

... other messages
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01SzvAdMUT45UdVL85Hfk5JG","name":"get_current_weather","input":{}}         }
```

## How litellm is involved

Litellm is not currently mapping the tool indexes. It currently assigns the tools the index of their chunk, and instead it needs to assign the tools based on their own index, not based on the chunk index. For example see here https://github.com/BerriAI/litellm/blob/main/litellm/llms/anthropic.py#L1190

### Additional contract requirements

During Anthropic streaming, tool-call indices are consecutive and zero-based in the order the tool calls occur. Text and other non-tool content blocks do not affect tool-call indices.
