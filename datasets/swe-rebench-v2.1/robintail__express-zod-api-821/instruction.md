`DELETE` endpoints with `requestBody` leads to an OpenAPI semantic error
It looks like OpenAPI spec forbids a request body for `DELETE` operations:
- According to https://www.rfc-editor.org/rfc/rfc9110.html#name-delete:
> Although request message framing is independent of the method used, content received in a DELETE request has no generally defined semantics, cannot alter the meaning or target of the request, and might lead some implementations to reject the request and close the connection because of its potential as a request smuggling attack
- According to https://stackoverflow.com/a/54980985:
> No, you cannot use the OpenAPI 3.0 Specification and Swagger tools to implement DELETE requests with a request body

---
### Steps to reproduce:
- add endpoint with `delete` method like this:
```
defaultEndpointsFactory.build({
  methods: ["delete"],
  input: z.object({}),
...
```
- call `new OpenAPI({...}).getSpecAsYaml()`
- validate generated spec (e.g. on https://editor.swagger.io/)

### Actual behaviour:
There is a semantic error `DELETE operations cannot have a requestBody` in OpenAPI spec

### Expected behaviour
OpenApi spec generates without `requestBody` for DELETE operations
