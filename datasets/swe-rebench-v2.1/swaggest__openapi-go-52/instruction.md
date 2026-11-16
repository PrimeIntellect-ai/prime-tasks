Security schemes validation error
Consider something like:

```go
var s openapi3.Spec

	spec := `openapi: 3.0.3
info:
  description: description
  license:
    name: Apache-2.0
    url: https://www.apache.org/licenses/LICENSE-2.0.html
  title: title
  version: 2.0.0
servers:
  - url: /v2
paths:
  /user:
    put:
      summary: updates the user by id
      operationId: UpdateUser
      requestBody:
        content:
          application/json:
            schema:
              type: string
        description: Updated user object
        required: true
      responses:
        "404":
          description: User not found
components:
  securitySchemes:
    api_key:
      in: header
      name: x-api-key
      type: apiKey
    bearer_auth:
      type: http
      scheme: bearer
      bearerFormat: JWT`

	if err := s.UnmarshalYAML([]byte(spec)); err != nil {
		log.Fatal(err)
	}
```

this results in:

```
oneOf constraint failed for SecuritySchemeOrRef with 0 valid results: map[SecurityScheme:oneOf constraint failed for SecurityScheme with 0 valid results: map[APIKeySecurityScheme:required key missing: name HTTPSecurityScheme:oneOf constraint failed for HTTPSecurityScheme with 2 valid results: map[] OAuth2SecurityScheme:required key missing: flows OpenIDConnectSecurityScheme:required key missing: openIdConnectUrl] SecuritySchemeReference:required key missing: $ref]
```

when there really shouldn't be any error. It's coming from the generated `openapi3/entities.go` but when I use the source json schema directly it gives no errors as it should, so I there must be something wrong with the generated validation code

Version: v0.2.24
