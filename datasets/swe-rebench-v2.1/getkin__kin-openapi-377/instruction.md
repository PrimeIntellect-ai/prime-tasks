Failure loading OpenAPI 3.0 spec when a ref to 'additionalProperties' exists
When trying to load an OpenAPI 3.0 file which includes a ref to "additionalProperties" the load panics

A minimal example:
```
openapi: 3.0.0
components:
  schemas:
    schema1:
      type: object
      additionalProperties:
        type: string
    schema2:
      type: object
      properties:
        prop:
          $ref: '#/components/schemas/schema1/additionalProperties'
```
