Definition generated improperly when multiple instances of a resource are inherited
Take the following example spec that contains 2 definitions: *resource* and *createResource*.  Resource both defines its own *_embedded* property and inherits *_embedded* from createResource.
 _embedded is the same in both cases except for the description.

```
swagger: '2.0'
info:
  title: Example
  version: 0.1.0
paths:
  /tasks:
    get:
      summary: Return a collection of tasks
      operationId: getTasks
      responses:
        '200':
          description: OK

definitions:
  resource:
    allOf:
    - $ref: '#/definitions/createResource'
    properties:
       _embedded:
        description: >-
          Test Description
        type: object
  createResource:
    properties:
       _embedded:
        description: >-
          Other Description
        type: object
```

Note the generated output below:
```
declare namespace Definitions {
  export interface CreateResource {
    /**
     * Other Description
     */
    _embedded?: {};
  }
  export interface Resource {
    /**
     * Other Description  // Expect this to be Test Description
     */
    _embedded?: {};
  }
}
```

Swagger editor shows the 2 resources with different descriptions, but the generated code has them with the same.  This example uses Description to demo the issue, the issue is not limited to the Description field.
