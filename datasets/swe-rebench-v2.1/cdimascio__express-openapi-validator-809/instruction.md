coerceTypes "array" is not working for query params
**Describe the bug**
From my understanding of the documentation, the coerceTypes option is set to 'true' by default. However, I am unable to modify this setting to other options, such as 'array'.

**To Reproduce**
- Create a basic openapi document with an object param that nests an array param
```json
{
  "paths": {
    "/api/route": {
      "get": {
        "parameters": [
          {
            "in": "query",
            "name": "property",
            "schema": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "values": { "type": "array", "items": { "type": "string" } }
              }
            }
          }
        ]
      }
    }
  }
}
```
- Configure coerceTypes to `array`
- perform a a request like `http://localhost/api/route?property[values]=value1`


**Actual behavior**
```json
{
 "errors": [
  {
   "path": "/query/property/values",
   "message": "must be array",
   "errorCode": "type.openapi.validation"
  }
 ]
}
```

**Expected behavior**
Pass validation and coerce the values properly to an array, as per documentation https://ajv.js.org/coercion.html

**Examples and context**
Not sure why but on a simpler case this is working and the value apparently is properly coerced to an array
`http://localhost/api/route?property=value1`
```json
{
  "paths": {
    "/api/route": {
      "get": {
        "parameters": [
         {
            "in": "query",
            "name": "property",
            "schema": { "type": "array", "items": { "type": "string" } }
          }
        ]
      }
    }
  }
}
```
