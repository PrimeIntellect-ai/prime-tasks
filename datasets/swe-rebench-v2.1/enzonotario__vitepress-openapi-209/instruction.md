"nullable" objects
### Current behavior

In OpenAPI you can create a nullable object with:
```yaml
type: [object, 'null']
properties:
  example:
    type: string
```

Currently, vitepress-openapi will not display the properties correctly.

### Desired behavior

If the object is nullable, it should still list all properties of nullable object and not just `object | null`

### Reproduction

_No response_

### Steps to reproduce

```json
{
  "openapi": "3.1.0",
  "info": {
    "title": "Nullable objects"
  },
  "servers": [
    {
      "url": "https://whatever.com",
      "description": "Mock Server"
    }
  ],
  "paths": {
    "/nullable": {
      "get": {
        "tags": [
          "Nullable"
        ],
        "summary": "Get nullable object",
        "description": "Yayy",
        "operationId": "getNullableObject",
        "responses": {
          "200": {
            "description": "OK",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "a": {
                      "type": [
                        "object",
                        "null"
                      ],
                      "properties": {
                        "a": {
                          "type": "number"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  "tags": [],
  "externalDocs": {}
}
```

![Image](https://github.com/user-attachments/assets/1443d6bc-df78-4ab7-8f54-9fb784658230)

### Logs and Error Messages

_No response_

### Other Information

_No response_

### Additional contract requirements

- When converting a nullable object schema with `name: { type: 'string' }` and `age: { type: 'integer' }` to a JSON example, produce `{ name: 'string', age: 0 }`.
