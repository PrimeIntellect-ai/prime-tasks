Panic while loading invalid document
Lib panics while loading invalid swagger definition with `LoadSwaggerFromData`:
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x1334b84]

goroutine 1 [running]:
[HIDDEN]
	/Users/rsukho/go/src/github.com/getkin/kin-openapi/openapi3/swagger_loader.go:525 +0xe4
github.com/getkin/kin-openapi/openapi3.(*SwaggerLoader).resolvePathItemRef(0xc0000972c0, 0xc000099110, 0xc00015a530, 0x5, 0xc000152580, 0x0, 0x0, 0x8)
	/Users/rsukho/go/src/github.com/getkin/kin-openapi/openapi3/swagger_loader.go:849 +0x3df
github.com/getkin/kin-openapi/openapi3.(*SwaggerLoader).ResolveRefsIn(0xc0000972c0, 0xc000099110, 0x0, 0x900, 0x13c8920)
	/Users/rsukho/go/src/github.com/getkin/kin-openapi/openapi3/swagger_loader.go:217 +0x839
github.com/getkin/kin-openapi/openapi3.(*SwaggerLoader).loadSwaggerFromDataInternal(0xc0000972c0, 0xc0000d2900, 0x836, 0x900, 0x836, 0x900, 0x100742f)
	/Users/rsukho/go/src/github.com/getkin/kin-openapi/openapi3/swagger_loader.go:150 +0xe7
github.com/getkin/kin-openapi/openapi3.(*SwaggerLoader).LoadSwaggerFromData(...)
	/Users/rsukho/go/src/github.com/getkin/kin-openapi/openapi3/swagger_loader.go:142
main.main()
	/Users/rsukho/go/src/github.com/zzell/issue1/main.go:10 +0xc5
exit status 2
```

I made a small snippet to reproduce the issue:

```go
package main

import (
	"log"

	"github.com/getkin/kin-openapi/openapi3"
)

func main() {
	_, err := openapi3.NewSwaggerLoader().LoadSwaggerFromData([]byte(doc))
	if err != nil {
		log.Fatal(err)
	}
}

var doc = `openapi: 3.0.0
info:
  version: 1.0.0
  title: Swagger Petstore
  license:
    name: MIT
servers:
  - url: 'http://petstore.swagger.io/v1'
paths:
  /pets:
    get:
      summary: List all pets
      operationId: listPets
      tags:
        - pets
      parameters:
        - name: limit
          in: query
          description: How many items to return at one time (max 100)
          required: false
          schema:
            type: integer
            format: int32
      responses:
        '200': # <--------------- PANIC HERE

    post:
      summary: Create a pet
      operationId: createPets
      tags:
        - pets
      responses:
        '201':
          description: Null response
        default:
          description: unexpected error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
  '/pets/{petId}':
    get:
      summary: Info for a specific pet
      operationId: showPetById
      tags:
        - pets
      parameters:
        - name: petId
          in: path
          required: true
          description: The id of the pet to retrieve
          schema:
            type: string
      responses:
        '200':
          description: Expected response to a valid request
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
        default:
          description: unexpected error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
components:
  schemas:
    Pet:
      type: object
      required:
        - id
        - name
      properties:
        id:
          type: integer
          format: int64
        name:
          type: string
        tag:
          type: string
    Pets:
      type: array
      items:
        $ref: '#/components/schemas/Pet'
    Error:
      type: object
      required:
        - code
        - message
      properties:
        code:
          type: integer
          format: int32
        message:
          type: string`
```

### Additional contract requirements

- When `LoadSwaggerFromData` loads the supplied document with a response entry whose value is null, it must return an error rather than panic.
