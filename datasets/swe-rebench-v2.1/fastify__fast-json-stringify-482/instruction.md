Ajv validation inside allOf
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the issue has not already been raised


### Issue

There is a fastify issue https://github.com/fastify/fastify/issues/4092
I reduced the test example.

```js
test('anyOf inside allOf', (t) => {
  t.plan(1)

  const schema = {
    anyOf: [
      {
        type: 'object',
        allOf: [
          {
            properties: {
              a: {
                anyOf: [
                  { const: 'A1' },
                  { const: 'A2' }
                ]
              }
            }
          },
          {
            properties: {
              b: { const: 'B' }
            }
          }
        ]
      }
    ]
  }

  const object = { a: 'A1', b: 'B' }
  const stringify = build(schema)
  const output = stringify(object)

  t.equal(output, JSON.stringify(object))
})
```

I'm working on that.
