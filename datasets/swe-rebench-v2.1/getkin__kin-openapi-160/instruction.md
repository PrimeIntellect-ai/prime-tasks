Receiving incorrect error, when endpoint is path with unsupported method
Hi, I've found that when I send request to a path with unsupported method, error message in response is "Path was not found" instead of ["Path doesn't support the HTTP method"](https://github.com/getkin/kin-openapi/blob/master/openapi3filter/router.go#L199)

Steps to reproduce:
1. Run a server, generated from OpenAPI specification. For example, [Petstore](https://github.com/deepmap/oapi-codegen/blob/master/examples/petstore-expanded/chi/petstore.go#L16) from OpenAPI examples
2. Send request to a path with unsupported method, for example PUT /users

Actual result:
```
{
    "message": "Path was not found"
}
```
Expected result:
```
{
    "message": "Path doesn't support the HTTP method"
}
```
