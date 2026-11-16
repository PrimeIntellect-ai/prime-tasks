[Bug]: Cursor IDE compatibility: tool_choice validation error when using {"type": "auto"} format - should support both OpenAI specs
### What happened?

I'm encountering an API validation error when using LiteLLM as a proxy for Claude models through Cursor IDE. The issue occurs when Cursor sends requests with `tool_choice: {"type": "auto"}` format, which LiteLLM rejects as invalid.

**Setup:**
- LiteLLM deployed as API proxy
- Cursor IDE configured to use LiteLLM endpoint with custom model `claude-sonnet-4-20250514`
- Using Cursor's Agent mode (which enables function calling)

**Expected Behavior:**
LiteLLM should accept `tool_choice: {"type": "auto"}` as it's a valid format used by some OpenAI-compatible clients.

**Actual Behavior:**
LiteLLM throws validation error: `Invalid tool choice, tool_choice={'type': 'auto'}. Please ensure tool_choice follows the OpenAI spec`

**Request payload from Cursor:**
```json
{
  "model": "claude-sonnet-4-20250514",
  "tools": [...],
  "stream": true,
  "system": [...],
  "messages": [...],
  "max_tokens": 4096,
  "temperature": 0.7,
  "tool_choice": {
    "type": "auto"
  }
}
```

The issue appears to be in the `validate_chat_completion_tool_choice` function which doesn't recognize the `{"type": "auto"}` format as valid, even though it should be equivalent to `"auto"`.


### Relevant log output

```shell
litellm.APIConnectionError: Invalid tool choice, tool_choice={'type': 'auto'}. Please ensure tool_choice follows the OpenAI spec
Traceback (most recent call last):
  File "/usr/lib/python3.13/site-packages/litellm/main.py", line 517, in acompletion
    init_response = await loop.run_in_executor(None, func_with_context)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/concurrent/futures/thread.py", line 59, in run
    result = self.fn(*self.args, **self.kwargs)
  File "/usr/lib/python3.13/site-packages/litellm/utils.py", line 1032, in wrapper
    result = original_function(*args, **kwargs)
  File "/usr/lib/python3.13/site-packages/litellm/main.py", line 922, in completion
    tool_choice = validate_chat_completion_tool_choice(tool_choice=tool_choice)
  File "/usr/lib/python3.13/site-packages/litellm/utils.py", line 6569, in validate_chat_completion_tool_choice
    raise Exception(
      f"Invalid tool choice, tool_choice={tool_choice}. Please ensure tool_choice follows the OpenAI spec"
    )
Exception: Invalid tool choice, tool_choice={'type': 'auto'}. Please ensure tool_choice follows the OpenAI spec
. Received Model Group=claude-sonnet-4-20250514
Available Model Group Fallbacks=None
```

### Are you a ML Ops Team?

No

### What LiteLLM version are you on ?

v1.73.2

### Twitter / LinkedIn details

_No response_
