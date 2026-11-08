openapi2conv: Operation-level externalDocs are not preserved
openapi2conv does not preserve `externalDocs` defined on an operation.

## Input
```yaml
swagger: '2.0'
info:
  version: 1.0.0
  title: title
paths:
  /test:
    get:
      externalDocs:
        url: https://example/operation
        description: Operation level documentation
      responses:
        '200':
          description: description
```

## Expected output
```yaml
openapi: 3.0.3
info:
  version: 1.0.0
  title: title
paths:
  /test:
    get:
      externalDocs:
        url: https://example/operation
        description: Operation level documentation
      responses:
        '200':
          description: description
```

## Actual output
```yaml
openapi: 3.0.3
info:
  version: 1.0.0
  title: title
paths:
  /test:
    get:
      responses:
        '200':
          description: description
```

## Additional context
Root-level and schema-level externalDocs fields are preserved correctly.
