Cannot find reference with allOf
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

4.5.3

### Plugin version

5.3.0

### Node.js version

16

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

12.2

### Description

I suspect it comes from https://github.com/fastify/fastify/pull/4049 shipped with fastify 4.2.0 but I cannot figure what is wrong with my case.
It used to work with  fastify 4.1.0 .

Maybe you have a clue.

### Steps to Reproduce

Schema is :
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "Test",
  "definitions": {
    "Problem": {
      "type": "object",
      "required": [
        "type"
      ],
      "additionalProperties": true,
      "properties": {
        "type": {
          "type": "string"
        }
      }
    },
    "ValidationFragment": {
      "type": "string"
    },
    "ValidationErrorProblem": {
      "type": "object",
      "allOf": [
        {
          "$ref": "#/definitions/Problem"
        },
        {
          "type": "object",
          "properties": {
            "validation": {
              "$ref": "#/definitions/ValidationFragment"
            }
          }
        }
      ]
    }
  },
  "additionalProperties": false,
  "type": "object"
}
```
Code is
```ts
import fastify from 'fastify';

const server = fastify();

const schema = require('./schema.json');
server.addSchema(schema);

server.post<{
}>(
  '/dummy',
  {
    schema: {
      response: {
        '400': {$ref: 'Test#/definitions/ValidationErrorProblem'},
      },
    }
  },
  async (_request, _reply) => {
    return 'OK'
  });

server.ready();
```
Error is :
```
node_modules/fastify/lib/route.js:326
              throw new FST_ERR_SCH_SERIALIZATION_BUILD(opts.method, url, error.message)
                    ^
FastifyError [Error]: Failed building the serialization schema for POST: /dummy, due to error Cannot find reference "#/definitions/ValidationFragment"
```

### Expected Behavior

It used to work with fastify 4.1.0. I would expect FJS to compile the schema.
