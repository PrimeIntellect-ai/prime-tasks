Maximum call stack size exceeded when $ref plain name fragment
Hi all,
writing this PR https://github.com/fastify/fastify/pull/1425, with the suggestion of Collina, I found that the `$ref` property doesn't support the URI that points to `$id` (alias plain name fragment format).

I write this test that should pass:

```
test('ref internal - plain name fragment', (t) => {
  t.plan(2)

  const schema = {
    title: 'object with $ref',
    definitions: {
      def: {
        $id: '#uri',
        type: 'object',
        properties: {
          str: {
            type: 'string'
          }
        },
        required: ['str']
      }
    },
    type: 'object',
    properties: {
      obj: {
        $ref: '#uri'
      }
    }
  }

  const object = {
    obj: {
      str: 'test'
    }
  }

  const stringify = build(schema)
  const output = stringify(object)

  try {
    JSON.parse(output)
    t.pass()
  } catch (e) {
    t.fail()
  }

  t.equal(output, '{"obj":{"str":"test"}}')
})
```

Double check with AJV, where it works as expected:

```
var Ajv = require('ajv')
var ajv = new Ajv({ allErrors: true }) // options can be passed, e.g. {allErrors: true}

const schema = {
  title: 'object with $ref',
  definitions: {
    def: {
      $id: '#uri',
      type: 'object',
      properties: {
        str: {
          type: 'string'
        }
      },
      required: ['str']
    }
  },
  type: 'object',
  properties: {
    obj: {
      $ref: '#uri'
    }
  }
}

const data = {
  obj: {
    str: 'test'
  }
}

var validate = ajv.compile(schema)
var valid = validate(data)
console.log(valid)
console.log(validate.errors)

```

I'm working on this if it is ok for you 👍
Any suggestion is welcome 😃
