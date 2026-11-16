Must add all child schemas to the Ajv if at least one of them should be validated
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the issue has not already been raised


### Issue

```js
test('object with ref and validated properties', (t) => {
  t.plan(1)

  const externalSchemas = {
    RefSchema: {
      $id: 'RefSchema',
      type: 'string'
    }
  }

  const schema = {
    $id: 'root',
    type: 'object',
    properties: {
      id: {
        anyOf: [
          { type: 'string' },
          { type: 'number' }
        ]
      },
      reference: { $ref: 'RefSchema' }
    }
  }

  const stringify = build(schema, { schema: externalSchemas })
  t.equal(stringify({ id: 1, reference: 'hi' }), '{"id":"foo","reference":"hi"}')
})
```
