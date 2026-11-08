Validation of application/x-yaml request body fails due to unhandled type map[interface{}]interface{}
**kin-openapi version:** v0.80.0

Hi, I'm trying out the new feature for validating request bodies with content type `application/x-yaml` but `openapi3filter.ValidateRequest` always returns the error: `request body has an error: doesn't match the schema: unhandled value of type map[interface {}]interface {}`.

Am I doing something wrong here (see also full example at the end) or is it a problem in the implementation?

[HIDDEN]

There is some ongoing discussion in the gopkg.in/yaml.v2 about the map key type, see for example here https://github.com/go-yaml/yaml/issues/384.

<details>
 <summary>Complete Example</summary>

```go
package main

import (
	"bytes"
	"context"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/getkin/kin-openapi/openapi3filter"
	legacyrouter "github.com/getkin/kin-openapi/routers/legacy"
	"net/http/httptest"
	"testing"
)

func TestOASValidation(t *testing.T) {
	// init router
	loader := openapi3.NewLoader()
	oas, _ := loader.LoadFromData([]byte(`
openapi: '3.0.0'
info:
  title: API
  version: 1.0.0
paths:
  '/path':
    post:
      requestBody:
        required: true
        content:
          application/x-yaml:
            schema:
              type: object
      responses:
        '200':
          description: x
          content:
            application/json:
              schema:
                type: string
`))
	router, _ := legacyrouter.NewRouter(oas)

	// validate request
	r := httptest.NewRequest("POST", "/path", bytes.NewReader([]byte(`
foo: bar
`)))
	r.Header.Set("Content-Type", "application/x-yaml")

	openapi3.SchemaErrorDetailsDisabled = true
	route, pathParams, _ := router.FindRoute(r)
	reqValidationInput := &openapi3filter.RequestValidationInput{
		Request:    r,
		PathParams: pathParams,
		Route:      route,
	}
	if err := openapi3filter.ValidateRequest(context.Background(), reqValidationInput); err != nil {
		// Validation failed with error: request body has an error: doesn't match the schema: unhandled value of type map[interface {}]interface {}
		t.Errorf("Validation failed with error: %v", err)
	}
}
```

</details>

### Additional contract requirements

- A request with `Content-Type: application/x-yaml` and a YAML object body must validate successfully when its request-body schema declares `type: object`.
