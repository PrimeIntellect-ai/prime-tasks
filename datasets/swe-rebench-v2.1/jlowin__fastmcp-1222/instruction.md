Default values in elicitation schemas error when attempting to Proxy
### Description

My setup is the folliowing: Client -> Proxy -> Server.  When the Server initiates elicitation, and the schema includes a default value, the proxy elicitation handler throws an error. The same schema works without using the proxy.

[HIDDEN]

I have provided a minimal code which reproduces that while it's possible to get an elicitation schema for the initial type, the inverse type creates a different schema and throws an error

The relevant lines of code are here:
https://github.com/jlowin/fastmcp/blob/5fc7aa04aa82da6c06e757b4916df977a3f88f0f/src/fastmcp/utilities/json_schema_type.py#L551-L570

The other thing which I checked is that the ElicitRequestParams do have the json schema from the original server here:
https://github.com/jlowin/fastmcp/blob/5fc7aa04aa82da6c06e757b4916df977a3f88f0f/src/fastmcp/server/proxy.py#L545-L552



### Example Code

```Python
from pydantic import BaseModel, Field, TypeAdapter
from fastmcp.utilities.json_schema_type import json_schema_to_type
from fastmcp.server.elicitation import get_elicitation_schema
import json


def create_type() -> BaseModel:

    class TestModel(BaseModel):
        content: str = Field(description="Your reply content")
        acknowledge: bool = Field(
            default=False,
            description="Send immediately or save as draft",
        )
    return TestModel


initial = create_type()
initial_schema = json.loads(initial.schema_json())
# schema["type"] = "object"
inverse = json_schema_to_type(initial_schema)

print("Original:", get_elicitation_schema(initial))
print("Inverse Schema:", TypeAdapter(inverse).json_schema())
print("Inverse:", get_elicitation_schema(inverse)) # Errors out because acknowledge becomes nullable
```

### Version Information

```Text
FastMCP version:                                                                 2.10.5
MCP version:                                                                     1.10.1
Python version:                                                                  3.12.4
Platform:                                                    macOS-13.5-arm64-arm-64bit
```

### Additional Context

The output of the example code below is here:
```
Original: {'properties': {'content': {'description': 'Your reply content', 'title': 'Content', 'type': 'string'}, 'acknowledge': {'default': False, 'description': 'Send immediately or save as draft', 'title': 'Acknowledge', 'type': 'boolean'}}, 'required': ['content'], 'title': 'TestModel', 'type': 'object'}
Inverse Schema: {'properties': {'content': {'title': 'Content', 'type': 'string'}, 'acknowledge': {'anyOf': [{'type': 'boolean'}, {'type': 'null'}], 'default': False, 'title': 'Acknowledge'}}, 'required': ['content'], 'title': 'TestModel', 'type': 'object'}
```

### Additional contract requirements

When an elicitation schema containing a default-valued, originally non-nullable field is forwarded through a proxy, the field must remain non-nullable and retain its default, and the elicitation must be able to proceed.
