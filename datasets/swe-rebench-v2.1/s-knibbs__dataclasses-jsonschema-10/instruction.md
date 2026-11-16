Generated JSON schema are causing Swagger validation warnings
The JSON references currently being generated aren't correct, instead of this:
```json
{"$ref": "#/definitions/Point", "type": "object"}
```
should be this:
```json
{"$ref": "#/definitions/Point"}
```
