Path in $ref is partually percent-encoded
### Q&A
 - OS: windows
 - Browser: chrome
 - Version: 76.0.3809.132
 - Method of installation: no installation, issue is presented at editor.swagger.io
 - Swagger-Editor version: current editor.swagger.io
 - Swagger/OpenAPI version: Swagger 2.0

### Content & configuration
<!-- Provide us with a way to see what you're seeing, so that we can help. -->

Swagger/OpenAPI definition:
```
swagger:` '2.0'
info:
  description: 'Swagger docs'
  title: API example
  version: '1.0'
host: server
basePath: /docs
paths:
  '/ws/person':
    get:
      parameters:
        - name: id
          type: number
          in: path
          description: 'person id'
          required: true
      description: Get person
      operationId: 'get_person'
      tags:
        - Person
      responses:
        '200':
          description: Ok
          schema:
            type: object
            properties:
              result:
                $ref: '#/definitions/custom%3A%3Anamespace%3A%3APerson'
definitions:
  'custom::namespace::Person':
    properties:
      id:
        type: number
      FirstName:
        type: string
      LastName:
        type: string
      Address:
        type: array
        items:
          $ref: '#/definitions/custom%3A%3Anamespace%3A%3AAddress'
  'custom::namespace::Address':
    properties:
      id:
        type: number
      street:
        type: string
      city:
        type: string
```

### How can we help?
<!-- Your question or problem goes here! -->
In order to generate JSON without warnings some part $ref needs to be percent encoded, and not. Is this correct behavior, or maybe bug.

Way to reproduce this issue:
* Current JSON that contains part without and part with percent encoding will not have warnings.
* If we convert $ref without percent encoding warning will popup `$ref: '#/definitions/custom::namespace::Person'`
* If we convert $ref with all characters percent encoding warning will popup `$ref: '%23%2Fdefinitions%2Fcustom%3A%3Anamespace%3A%3APerson'`

### Additional contract requirements

The schema name extracted from a `$ref` must be decoded for both supported document versions:

- OpenAPI 3 references of the form `#/components/schemas/<name>`.
- Swagger 2.0 references of the form `#/definitions/<name>`.

Decoding resolves both JSON Pointer escapes and percent-encoding:

- `~1` becomes `/` and `~0` becomes `~`.
- Percent-encoded characters are decoded (for example `%2B` becomes `+` and `%3A` becomes `:`).

Concrete results that must hold:

- `#/components/schemas/a~1b%2Bc` yields `a/b+c`.
- `#/definitions/custom%3A%3Anamespace%3A%3APerson` yields `custom::namespace::Person`.
- `#/components/schemas/~1~1~0~0` yields `//~~`.

If the extracted name contains malformed percent-encoding that cannot be decoded, the name must be returned unchanged (after JSON Pointer escapes have been resolved) rather than raising an error. For example, `#/components/schemas/%25%d` yields `%25%d`.
