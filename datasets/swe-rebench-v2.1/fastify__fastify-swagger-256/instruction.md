Keep custom fields that start with 'x-' intact in swagger
<!--
Before you submit an issue we recommend you visit [Fastify Help](https://github.com/fastify/help) and ask any questions you have or mention any problems you've had getting started with Fastify.

**Please read this entire template before posting any issue. If you ignore these instructions
and post an issue here that does not follow the instructions, your issue might be closed,
locked, and assigned the `missing discussion` label.**
-->

## 🚀 Feature Proposal

I propose to include all fields that start with 'x-' (as per swagger spec https://swagger.io/docs/specification/2-0/swagger-extensions/) in the final swagger specification.  Currently, such extensions in parameters, responses, bodies, etc. are included (because they are passed verbatim), but the path object only keeps properties that are specifically hard-coded.

## Motivation

That would be useful for custom schema renderers that can utilize that additional information about paths.

## Example

```js
  fastify.route({
    method: 'GET',
    url: '/path',
    schema: {
      summary: 'Some method',
      response: {
        200: '...'
      },
      'x-custom-field': 'custom info'
    },
    ...
  })
```

This code should generate something like:

```json
{
  "paths": {
    "/path": {
      "get": {
        ...,
        "x-custom-field": "custom info"
      }
    }
  }
}
```
