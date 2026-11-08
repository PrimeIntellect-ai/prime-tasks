Add support for canonical and inline referencing
Spec: http://json-schema.org/latest/json-schema-core.html#anchor25

I suggest we start by supporting local definitions only:

```json
{
  "definitions": {
    "address": {
      "type": "object",
      "properties": {
        "street_address": { "type": "string" },
        "city":           { "type": "string" },
        "state":          { "type": "string" }
      },
      "required": ["street_address", "city", "state"]
    }
  },

  "type": "object",

  "properties": {
    "billing_address": { "$ref": "#/definitions/address" },
    "shipping_address": { "$ref": "#/definitions/address" }
  }
}
```

(Sample JSONSchema source extracted from http://spacetelescope.github.io/understanding-json-schema/structuring.html)
