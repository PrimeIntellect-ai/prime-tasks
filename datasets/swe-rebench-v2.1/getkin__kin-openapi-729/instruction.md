Validation of `multipart/form-data` request fails for schemas containing `allOf`
Hello,

I get an error when validating a request with the following Spec

```yaml
openapi: 3.0.0
info:
  title: 'Validator'
  version: 0.0.1
paths:
  /test:
    post:
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required:
                - file
              allOf:
              - $ref: '#/components/schemas/Category'
              - properties:
                  file:
                    type: string
                    format: binary
                  description:
                    type: string
      responses:
        '200':
          description: Created

components:
  schemas:
    Category:
      type: object
      properties:
        name:
          type: string
      required:
      - name
```

Depending on the request itself, the following error occurs at the very first boundary.

```
request body has an error: failed to decode request body: part file: undefined
```
