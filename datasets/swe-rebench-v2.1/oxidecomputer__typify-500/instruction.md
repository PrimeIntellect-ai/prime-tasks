Merge oneOf with many compatible enums of a single value
https://github.com/OAI/OpenAPI-Specification/issues/348#issuecomment-1484163189 is apparently the best way to describe enum values, like

```json
    "enum-value-descriptions": {
      "type": "object",
      "description": "https://github.com/OAI/OpenAPI-Specification/issues/348#issuecomment-1484163189",
      "oneOf": [
        {
          "enum": ["A"],
          "description": "An A"
        },
        {
          "enum": ["B"],
          "description": "A B"
        }
      ]
    }
```

Typify generates a bunch of variants for the above, when they could be collapsed into a single Rust enum.
