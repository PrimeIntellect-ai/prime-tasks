Params with regex breaking docs
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

3.24.1

### Plugin version

4.12.6

### Node.js version

14.18.2

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

11.6

### Description

Similar to <https://github.com/fastify/fastify-swagger/issues/100>.


### Steps to Reproduce

Route Code:

```typescript
fastify.get<{ Params: { code: string } }>(
  '/api/v1/postalcode-jp/:code(^[0-9]{7}$)',
  {
    schema: {
      description: 'search addresses by postalcode',
      tags: ['test'],
      params: {
        $schema: 'http://json-schema.org/draft-07/schema#',
        type: 'object',
        properties: { code: { type: 'string', minLength: 7, maxLength: 7 } },
        required: ['code'],
        additionalProperties: false,
      },
    },
  },
  async (req, rep) => rep.send({ ...req.params }),
)
```

Plugin Options:

```typescript
fastify
  .register(fastifySwagger, {
    routePrefix: '/api-doc',
    openapi: {
      info: {
        title: 'Test API',
        description: 'testing the fastify swagger api',
        version: '1.0.0',
      },
      servers: [
        {
          url: `http://localhost:${process.env.LISTEN_PORT_WWW || 3000}/api/v1`,
        },
      ],
    },
    hideUntagged: true,
    exposeRoute: true,
  })
```

----

Result:

<img width="798" alt="スクリーンショット 2021-12-07 21 02 35" src="https://user-images.githubusercontent.com/26789317/145025933-80983700-7350-4a13-a718-75217d50dacf.png">



### Expected Behavior

Should be remove regex from request url.
Correct Request URL: `http://localhost:3001/api/v1/postalcode-jp/1234567`

### Additional contract requirements

The documented request path keeps the parameter name and removes the parameter's regular expression, so the reported route `/api/v1/postalcode-jp/:code(^[0-9]{7}$)` is documented as `/api/v1/postalcode-jp/{code}`.
