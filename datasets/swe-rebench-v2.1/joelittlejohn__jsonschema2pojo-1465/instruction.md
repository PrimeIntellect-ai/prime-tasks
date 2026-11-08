Properties with special character in the name (#, /, etc) cause IllegalArgumentException 'Path not present' when using 1.1.2
After updating to version [org.jsonschema2pojo:jsonschema2pojo-gradle-plugin](https://togithub.com/joelittlejohn/jsonschema2pojo) `1.1.2` of the plugin, we are no longer able to generate classes when the attributes contain `#`
This was possible on version `1.1.1`
For example `VERSV#`

```
{
  "$schema": "http://json-schema.org/draft-06/schema#",
  "$ref": "#/definitions/BusinessData",
  "definitions": {
    "BusinessData": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "VERSV#": {
          "type": "string"
        },
        "HEADER": {
          "$ref": "#/definitions/Header"
        }
      },
      "title": "BusinessData"
    }
}
```

### Additional contract requirements

Schema properties whose names contain characters such as `#` or `/` must be treated as individual property names during class generation, without a `Path not present` failure.
