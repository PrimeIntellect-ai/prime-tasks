bug: JSON schema references are incorrectly resolved when mulitple properties use the same reference
### Singer SDK Version

0.46.4

### Is this a regression?

- [x] Yes

### Python Version

NA

### Bug scope

Taps (catalog, state, etc.)

### Operating System

NA

### Description

```python
from singer_sdk.singerlib resolve_schema_references

resolve_schema_references(
    {
        "type": "object",
        "properties": {
            "min_compute_units": {"$ref": "components#/schemas/ComputeUnit"},
             "max_compute_units": {"$ref": "components#/schemas/ComputeUnit"},
        },
    },
    {"components": {"schemas": {"ComputeUnit": {"type": "number"}}}},
)

# Expected:
# {
#     "type": "object",
#     "properties": {
#         "min_compute_units": {"type": "number"},
#         "max_compute_units": {"type": "number"},
#     },
# }

# Actual
# {
#     "type": "object",
#     "properties": {
#         "min_compute_units": {"type": "number"},
#         "max_compute_units": {},  # Presumably ComputeUnit had already been visited
#     },
# }
```


### Link to Slack/Linen

_No response_
