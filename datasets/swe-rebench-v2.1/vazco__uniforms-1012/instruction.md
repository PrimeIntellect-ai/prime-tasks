Unsupported field type: undefined
Hi, we are getting an error "Unsupported field type: undefined" when using the json schema below.
If we change the reference in `my_property` to `GoodType` then the form is rendered without errors. It seems to be a problem with `BadType` being a `$ref`... thanks

react@17.0.2
uniforms-bridge-json-schema@3.5.5
unforms-material@3.5.5
uniforms@3.5.5

```
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$ref": "#/definitions/MyObjectType",
  "definitions": {
    "MyObjectType": {
      "type": "object",
      "properties": {
        "my_property": {
          "$ref": "#/definitions/BadType"
        }
      },
      "required": ["my_property"],
      "additionalProperties": false
    },
    "BadType": {
      "$ref": "#/definitions/GoodType"
    },
    "GoodType": {
      "type": "integer"
    }
  }
}
```
