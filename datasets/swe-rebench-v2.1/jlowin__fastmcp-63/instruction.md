String args containing ints are failing validation
Minimal repro:

```python
from fastmcp import FastMCP


mcp = FastMCP("Demo 🚀")

@mcp.tool()
def concat_strings(a: str, b: str) -> str:
    """
    Concatenate two strings together.
    """
    return a + b
```

When this is called with e.g. `"a"` and `"1"`, a Pydantic error is returned:

```
================================ Human Message =================================

can you concatenate the string "a" and the string "2" for me?
================================== Ai Message ==================================

[{'text': 'I\'ll help you concatenate the strings "a" and "2" using the `concat_strings` function.', 'type': 'text'}, {'id': 'toolu_01DkxqVusERHFyBrZyYMNHuZ', 'input': {'a': 'a', 'b': '2'}, 'name': 'concat_strings', 'type': 'tool_use'}]
Tool Calls:
  concat_strings (toolu_01DkxqVusERHFyBrZyYMNHuZ)
 Call ID: toolu_01DkxqVusERHFyBrZyYMNHuZ
  Args:
    a: a
    b: 2
...
================================= Tool Message =================================
Name: concat_strings

Error: ExceptionGroup('unhandled errors in a TaskGroup', [ExceptionGroup('unhandled errors in a TaskGroup', [ToolException([TextContent(type='text', text='Error executing tool concat_strings: 1 validation error for concat_stringsArguments\nb\n  Input should be a valid string [type=string_type, input_value=2, input_type=int]\n    For further information visit https://errors.pydantic.dev/2.10/v/string_type')])])])
 Please fix your mistakes.
...
```
