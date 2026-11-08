Pull #3250 changed the openapi returned types for views, breaking anything code-gen'ing types for each schema.
This change: https://github.com/goadesign/goa/pull/3250/files unexpectedly broke a lot of stuff for our app unfortunately.  My UI devs use [orval.dev](http://orval.dev/) to codegen from the openapi3 spec and what was a single response type that all the code used (for all the views) and which would just have some properties missing depending on the view is now a variety of completely new types, per view so the generated code now expects the client to basically explicitly handle 'each' type.
ie
For the same design, same return went from:
```
responses:
  "200":
...
content:
  application/json:
        schema:
            description: 'Response body may alternatively be one of #/components/schemas/GetNFDOKResponseBodyTiny, #/components/schemas/GetNFDOKResponseBodyThumbnail, #/components/schemas/GetNFDOKResponseBodyBrief or #/components/schemas/GetNFDOKResponseBodyFull'
            $ref: '#/components/schemas/NfdRecord'
```
to:
```
content:
  application/json:
    schema:
      anyOf:
        - $ref: '#/components/schemas/GetNFDOKResponseBodyTiny'
        - $ref: '#/components/schemas/GetNFDOKResponseBodyThumbnail'
        - $ref: '#/components/schemas/GetNFDOKResponseBodyBrief'
        - $ref: '#/components/schemas/GetNFDOKResponseBodyFull'
        - $ref: '#/components/schemas/GetNFDOKResponseBody'
```
so all existing code ends up completely breaking because it's a wholesale change across the board of all structures, all returns, breaks api hooks, everything.
Anyone code-gen'ing from the openapi file will create a massive breaking change.

This break occurred going to 3.11.1.

### Additional contract requirements

- In the multiple-view OpenAPI output, the `/tiny` response schema must use `$ref: '#/components/schemas/TestEndpointTinyResponseBodyTiny'`.
- In the multiple-view OpenAPI output, the `Result` component schema must not include a `description` field.
- In the multiple-view OpenAPI output, the `TestEndpointTinyResponseBodyTiny` component schema must include the description `TestEndpointTinyResponseBody result type (tiny view)`.
- In the multiple-view OpenAPI output, a response whose result type has several views must reference a single shared schema named after the result type's type name (`Result` for the multiple-views design), and must not use an `anyOf` list of per-view schemas.
