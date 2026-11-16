oas3-valid-(content-)schema-example: Problem with nullable
**Describe the bug**

It seems that in some cases the rules oas3-valid-schema-example and oas3-valid-content-schema-example fail although the examples are valid. Seems to be an issue with nullable / null values.

I get in the command line:
```
  59:33  error  oas3-valid-content-schema-example  `1` property type should be string
 167:25  error  oas3-valid-content-schema-example  `1` property type should be string
 167:25  error  oas3-valid-schema-example          `1` property type should be string
```

**To Reproduce**

OpenAPI document openapi.yaml:
```
openapi: 3.0.2
info:
  version: 1.0.0
  title: openEO API
  description: ...
  contact:
    name: openEO Consortium
    url: 'http://www.openeo.org'
    email: openeo@list.tuwien.ac.at
  license:
    name: Apache 2.0
    url: 'http://www.apache.org/licenses/LICENSE-2.0.html'
tags:
  - name: EO Data Discovery
    description: ...
servers:
  - url: 'https://localhost/api'
    description: ...
paths:
  /collections:
    get:
      summary: Basic metadata for all datasets
      operationId: list-collections
      description: ...
      tags:
        - EO Data Discovery
      responses:
        '200':
          description: A list of collections and related links.
          content:
            application/json:
              schema:
                title: Collections Response
                type: object
                required:
                  - collections
                properties:
                  collections:
                    type: array
                    items:
                      $ref: '#/components/schemas/collection'
                example:
                  collections:
                    - extent:
                        temporal:
                          interval:
                            - - '2000-02-01T00:00:00Z'
                              - null
components:
  schemas:
    collection:
      title: STAC Collection
      type: object
      required:
        - extent
      properties:
        extent:
          type: object
          title: STAC Collection Extent
          description: ...
          required:
            - spatial
            - temporal
          properties:
            temporal:
              description: The *potential* temporal extent of the features in the collection.
              type: object
              properties:
                interval:
                  description: ...
                  type: array
                  minItems: 1
                  items:
                    description: ...
                    type: array
                    minItems: 2
                    maxItems: 2
                    items:
                      type: string
                      format: date-time
                      nullable: true
                    example:
                      - '2011-11-11T12:22:11Z'
                      - null
```

.spectral.yml
```
extends: "spectral:oas"
```

Run: `spectral lint openapi.yaml`

**Expected behavior**

No warnings/errors

**Environment (remove any that are not applicable):**
 - Library version: 5.0.0
 - OS: Windows 10
