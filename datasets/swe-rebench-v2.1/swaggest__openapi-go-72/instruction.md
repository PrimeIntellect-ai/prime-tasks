req/resp struct using generic could cause semantic error in openapi output
**Describe the bug**
If req/resp struct using generic, like `type req[T any] struct {}`, generated openapi output will contains schema with name like `Req[Blabla]`, and Swagger Editor complains it as semantic error


**To Reproduce**
Take the example code in README, I modify req/resp to use generic:

```go
package main

import (
	"fmt"
	"github.com/swaggest/openapi-go/openapi3"
	"log"
	"net/http"
	"time"
)

func handleError(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	reflector := openapi3.Reflector{}
	reflector.Spec = &openapi3.Spec{Openapi: "3.0.3"}
	reflector.Spec.Info.
		WithTitle("Things API").
		WithVersion("1.2.3").
		WithDescription("Put something here")

	type req[T any] struct {
		ID     string `path:"id" example:"XXX-XXXXX"`
		Locale string `query:"locale" pattern:"^[a-z]{2}-[A-Z]{2}$"`
		Title  string `json:"string"`
		Amount uint   `json:"amount"`
		Items  []struct {
			Count uint   `json:"count"`
			Name  string `json:"name"`
		} `json:"items"`
	}

	type resp[T any] struct {
		ID     string `json:"id" example:"XXX-XXXXX"`
		Amount uint   `json:"amount"`
		Items  []struct {
			Count uint   `json:"count"`
			Name  string `json:"name"`
		} `json:"items"`
		UpdatedAt time.Time `json:"updated_at"`
	}

	putOp := openapi3.Operation{}

	handleError(reflector.SetRequest(&putOp, new(req[time.Time]), http.MethodPut))
	handleError(reflector.SetJSONResponse(&putOp, new(resp[time.Time]), http.StatusOK))
	handleError(reflector.SetJSONResponse(&putOp, new([]resp[time.Time]), http.StatusConflict))
	handleError(reflector.Spec.AddOperation(http.MethodPut, "/things/{id}", putOp))

	getOp := openapi3.Operation{}

	handleError(reflector.SetRequest(&getOp, new(req[time.Time]), http.MethodGet))
	handleError(reflector.SetJSONResponse(&getOp, new(resp[time.Time]), http.StatusOK))
	handleError(reflector.Spec.AddOperation(http.MethodGet, "/things/{id}", getOp))

	schema, err := reflector.Spec.MarshalYAML()
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println(string(schema))
}

```

which will output:

```yaml
openapi: 3.0.3
info:
  description: Put something here
  title: Things API
  version: 1.2.3
paths:
  /things/{id}:
    get:
      parameters:
      - in: query
        name: locale
        schema:
          pattern: ^[a-z]{2}-[A-Z]{2}$
          type: string
      - in: path
        name: id
        required: true
        schema:
          example: XXX-XXXXX
          type: string
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Resp[TimeTime]'
          description: OK
    put:
      parameters:
      - in: query
        name: locale
        schema:
          pattern: ^[a-z]{2}-[A-Z]{2}$
          type: string
      - in: path
        name: id
        required: true
        schema:
          example: XXX-XXXXX
          type: string
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Req[TimeTime]'
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Resp[TimeTime]'
          description: OK
        "409":
          content:
            application/json:
              schema:
                items:
                  $ref: '#/components/schemas/Resp[TimeTime]'
                type: array
          description: Conflict
components:
  schemas:
    Req[TimeTime]:
      properties:
        amount:
          minimum: 0
          type: integer
        items:
          items:
            properties:
              count:
                minimum: 0
                type: integer
              name:
                type: string
            type: object
          nullable: true
          type: array
        string:
          type: string
      type: object
    Resp[TimeTime]:
      properties:
        amount:
          minimum: 0
          type: integer
        id:
          example: XXX-XXXXX
          type: string
        items:
          items:
            properties:
              count:
                minimum: 0
                type: integer
              name:
                type: string
            type: object
          nullable: true
          type: array
        updated_at:
          format: date-time
          type: string
      type: object

```

Then paste it to https://editor.swagger.io/, it will complain `Component names can only contain the characters A-Z a-z 0-9 - . _`, although req/resp displayed correctly

**Expected behavior**
Output schema name should not contain bracket

**Additional context**
Nothing else and thanks for your library ❤️

### Additional contract requirements

- For generic request and response structs, generated component schema names and references to those schemas must not contain `[` or `]`.
