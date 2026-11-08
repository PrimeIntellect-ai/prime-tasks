oneof schema error improvment
**Context:**
currently, the library when validating an input against a schema and when an error occurred it returns schema error contains scheme filed where the error happens or input is invalid, under some circumstance, this is still not a piece of useful information to exactly know what happened behind the scene.

**Pain:**
Inappropriate error message returned when input matches more than "oneof" scheme.

**Goal:**
return a different error to distinguish input match more than oneof schemas (conflict) from input does not match oneof schemas.

**Got:**
`Error at "/address": Doesn't match schema "oneOf"`

**Expected:**
`Error at "/address": Conflict input match all oneof schemas"`

**Reproduce:**
```go
package main

import (
	"fmt"

	"github.com/getkin/kin-openapi/openapi3"
)

func main() {
	data := map[string]interface{}{
		"name":      "kin-openapi",
		"address": "127.0.0.1",
	}
	s, err := openapi3.NewSwaggerLoader().LoadSwaggerFromData([]byte(api))
	if err != nil {
		panic(err)
	}
	err = s.Components.Schemas["Server"].Value.VisitJSON(data)
	fmt.Println(err)

	//
}

var api =
`components:
  schemas:
    Server:
      properties:
        address:
          oneOf:
            - $ref: "#/components/schemas/ip-address"
            - $ref: "#/components/schemas/domain-name"
        name:
          type: string
      type: object
    domain-name:
      maxLength: 10
      minLength: 5
      pattern: "((([a-zA-Z0-9_]([a-zA-Z0-9\\-_]){0,61})?[a-zA-Z0-9]\\.)*([a-zA-Z0-9_]([a-zA-Z0-9\\-_]){0,61})?[a-zA-Z0-9]\\.?)|\\."
      type: string
    ip-address:
      pattern: "^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"
      type: string
openapi: "3.0.1"
`
```

**Note:**
* Releated to https://github.com/getkin/kin-openapi/blob/master/openapi3/schema.go#L850.
* Oneof in the above example added for only to reproduce otherwise should be anyof.

**Suggested Solution:**

[HIDDEN]

### Additional contract requirements

For the reproduced input, a conflict error identifies the `/address` location through its JSON pointer and its error text is `input matches more than one oneOf schemas`. The expected-output wording above describes this conflict-specific outcome; the exact text is the conflict message used by this library. An input matching no `oneOf` alternatives must remain distinguishable from an input matching multiple alternatives.
