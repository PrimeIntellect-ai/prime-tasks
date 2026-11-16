Cannot create a useable schema
I am taking the reverse road most usually take by generating openapi3 documentation from a minimal http framework on top of chi, the start was pretty fast and I can generate everything I need for the request path arguments but I am stuck trying to generate a schema for the `requestBody` of an operation, my best attempt so far is:


```go
type Pet struct {
  Id   string `json:"id"`
  Name string `json:"name"`
}

gen := openapi3gen.NewGenerator()

// bodyField points to `Pet` reflected type
bodySchema, err := gen.GenerateSchemaRef(bodyField.Type)
// error is checked but I removed it for clarity

body := openapi3.NewRequestBody()
body.Content = openapi3.NewContentWithJSONSchema(bodySchema.Value)
bodyRef := &openapi3.RequestBodyRef{
  Value: body,
}

op.RequestBody = bodyRef
swagger.AddOperation(pattern, method, op)
```

Aside from being really verbose (there may be faster way to do things but that's the best I found for now) this works but generates:

```json
{
  "content": {
    "application/json": {
      "schema": {
        "properties": {
          "id": {
            "$ref": "string"
          },
          "name": {
            "$ref": "string"
          }
        },
        "type": "object"
      }
    }
  }
}
```

this cause the viewers to try and request `<my-domain>/string` and i am not sure what I missed, from what I understand internal references should start with "#" but I see no way of influencing what ref are generated and I feel my lack of familiarity with openapi3 does not help xD

Any help or pointer in the right direction will be greatly appreciated :)

### Additional contract requirements

- Package `openapi3gen` must expose `NewSchemaRefForValue(value interface{}, opts ...Option) (*openapi3.SchemaRef, map[*openapi3.SchemaRef]int, error)`. It generates an OpenAPI v3 `SchemaRef` from the Go type of `value`, applying any supplied options. It returns the generated root schema reference, a map counting how many times each schema reference appears in the generated document, and an error.
- Package `openapi3gen` must expose the functional-option type `Option` and the option `UseAllExportedFields() Option`. When supplied to `NewSchemaRefForValue`, `UseAllExportedFields` makes every exported struct field a schema property regardless of whether it has a `json` tag; the property name is the field name, or the value of the field's `yaml` tag when one is present.
- A cyclic type must produce a `*CycleError` (package `openapi3gen`) and a nil root schema.
- An `int` field must generate an integer schema with no `format`.
- A `float64` field must generate a number schema that includes `"format": "double"`.
