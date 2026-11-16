Examples > Value: with array of value - problem
Hi @codekie ,

I have a strange issue, with the "value" property in an example.

Path

 ```
 /lists/audiences:
    parameters:
      - $ref: '#/components/parameters/X-ApiKey'
    get:
      summary: Get all audience configurations
      tags:
        - Lists - Audience
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/listsAudienceResults'
              examples:
                sample-list-audiences:
                  $ref: '#/components/examples/sample-list-audiences'
      operationId: get-audience-lists
      description: |-
        Returns a list of audience configurations.
        The configurations are returned sorted by name.
```

Components - Schema
```
components:
  schemas:
    listsAudienceResults:
      description: An audience configuration result.
      type: object
      properties:
        'value':
          description: 'Result of the audience configurations, based on the query options.'
          type: array
          items:
            $ref: '#/components/schemas/listsAudienceResultData'
        '@count':
            $ref: '#/components/schemas/link@count'
        '@nextlink':
            $ref: '#/components/schemas/link@nextlink'
```

Components - Example
```
    sample-list-audiences:
      value:
        value:
          - id: 12345-6789-01234-567-890
            tenant: 12345-6789-3333-1111-2222
            name: Master Contact list
            apiName: master_contact
            systemFields:
              mobile: MASTER.MOBILE
              language: MASTER.LANGUAGE
            type: Userlist
            requireSegment: true
            created: '2020-01-31T10:31:21.286Z'
            brands:
              - brandName: Demo
                brandId: 12345-6789-5555-6666-7777
        '@count': 68
        '@nextLink': https://api.demo.com/v2/lists/audiences?$count=true&$top=3&$skip=3
      summary: A sample of list of audience configurations response
```

When I run the validation check, it always throws the following error:
```
Errors found.

[
    {
        "type": "Validation",
        "message": "should be object",
        "keyword": "type",
        "dataPath": "",
        "schemaPath": "#/type",
        "params": {
            "type": "object"
        },
        "examplePath": "/paths/~1lists~1audiences/get/responses/200/content/application~1json/examples/sample-list-audiences/value/value"
    }
]
```

If I rename the "value" property in the schema and in the example to something else, like "data", the example is valid and no error is thrown.

Could it be that "value" property is a special property in the validation library, which causes the error to occur for a nested "value" property?
