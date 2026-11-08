Duplicate error reason for request parameter when it is required
When I define a request parameter which is required I get the message `value is required but missing` twice when I call `openapi3filter.RequestError.Error()`.

Schema:
```yml
#...
parameters:
  - name: 'hostname'
    in: query
    description: '...'
    schema:
      type: string
    required: true
#...
```

Code for validation:
```go
if err := openapi3filter.ValidateRequest(c.Request.Context(), requestValidationInput); err != nil {
	c.String(400, err.Error())
	c.Abort()
	return
}
```
Message when the parameter is missing:
`parameter "hostname" in query has an error: value is required but missing: value is required but missing`
