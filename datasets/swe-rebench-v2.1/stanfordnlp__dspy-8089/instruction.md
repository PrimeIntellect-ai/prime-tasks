[Bug] New defaults handling for Tools creates TypeError if assigned "Any"
### What happened?

`TypeError: 'str' object does not support item assignment` occurs a tool argument has a default value but no type hint: https://github.com/stanfordnlp/dspy/blob/main/dspy/primitives/tool.py#L122

### Steps to reproduce

```
def my_tool(limit = 120):
    return True

agent  = dspy.ReAct(SomeSig, tools=[my_tool])
```
Gives the following error:
```
File ...dspy/predict/react.py:24, in ReAct.__init__(self, signature, tools, max_iters)
     21 self.signature = signature = ensure_signature(signature)
     22 self.max_iters = max_iters
---> 24 tools = [t if isinstance(t, Tool) else Tool(t) for t in tools]
     25 tools = {tool.name: tool for tool in tools}
     27 inputs = ", ".join([f"`{k}`" for k in signature.input_fields.keys()])

File .../dspy/primitives/tool.py:61, in Tool.__init__(self, func, name, desc, args, arg_types, arg_desc)
     58 self.arg_types = arg_types
     59 self.arg_desc = arg_desc
---> 61 self._parse_function(func, arg_desc)

File .../dspy/primitives/tool.py:124, in Tool._parse_function(self, func, arg_desc)
    [HIDDEN]
    125 if arg_desc and k in arg_desc:
    126     args[k]["description"] = arg_desc[k]

TypeError: 'str' object does not support item assignment
```
Adding a type hint does not give the error, e.g. `def my_tool(limit: int = 120):`

### DSPy version

2.6.5

### Additional contract requirements

- Wrapping a callable as a `Tool` must not raise the reported `TypeError` when a parameter has a default value but no type hint.
- The argument schema for such a parameter must retain its default value.
