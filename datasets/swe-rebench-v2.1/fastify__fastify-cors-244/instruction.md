Allow the special `*` value in `array` in `origin` option
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the feature has not already been requested


### 🚀 Feature Proposal

Recognise the special `*` value in `array` type `origin` option.

### Motivation

When using this plugin with [env-schema](https://github.com/fastify/env-schema) or [fastify-env](https://github.com/fastify/fastify-env), I have to switch from `string` in dev (for `*`) to `array` in production (with `separator: ','` for multiple origins).

### Example

``` javascript
import fastify from 'fastify'
import fastifyCors from '@fastify/cors'
import envSchema from 'env-schema'

const config = envSchema({
  dotenv: true,
  schema: {
    type: 'object',
    properties: {
      CORS_ORIGIN: {
        type: 'string',
        separator: ',',
        default: '*'
      }
    }
  }
})

const server = fastify()

server.register(fastifyCors, {
  origin: config.CORS_ORIGIN
})

server.listen()
```
