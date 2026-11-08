🪲 No further validation in the presence of anyOf. Always true.
The reason for this change: #850

## Test case (add in `openapi3filter/validate_request_test.go`):

We are waiting for the error `minimum string length is 17`, but there is no error.

```go
func TestValidateRequestInvalidStringLength(t *testing.T) {
	const spec = `
openapi: 3.0.0
info:
  title: 'Validator'
  version: 0.0.1
paths:
  /tech:
    post:
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                vehicle:
                  $ref: "#/components/schemas/Vehicle"
      responses:
        '200':
          description: Ok

components:
  schemas:
    Vehicle:
      type: object
      properties:
        identifiers:
          type: object
          properties:
            vin:
              type: string
              minLength: 17
              maxLength: 17
            body:
              type: string
              minLength: 7
              maxLength: 15
          anyOf:
            - required: [ vin ]
            - required: [ body ]
`

	body := strings.NewReader(`{"vehicle":{"identifiers":{"vin":"BAD"}}}`)
	req, err := http.NewRequest(http.MethodPost, "/tech", body)
	require.NoError(t, err)

	req.Header.Add("Content-Type", "application/json")

	router := setupTestRouter(t, spec)
	route, pathParams, err := router.FindRoute(req)
	require.NoError(t, err)

	err = ValidateRequest(context.Background(), &RequestValidationInput{
		Request:     req,
		PathParams:  pathParams,
		Route:       route,
		QueryParams: req.URL.Query(),
	})
	require.ErrorContains(t, err, "minimum string length is 17")
}
```

Similar properties are similarly not validated. `minLength` is taken as an example.

### Additional contract requirements

When a request body is validated against a schema with `anyOf` on a nested object, applicable constraints on that object's properties must still be enforced. In particular, the reported payload with `vehicle.identifiers.vin` shorter than its `minLength: 17` must produce a validation error; this also applies to similar property constraints.
