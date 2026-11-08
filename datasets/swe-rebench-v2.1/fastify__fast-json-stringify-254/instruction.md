Validation issue with enum
<!--
Before you submit an issue we recommend you visit [Fastify Help](https://github.com/fastify/help) and ask any questions you have or mention any problems you've had getting started with Fastify.

**Please read this entire template before posting any issue. If you ignore these instructions
and post an issue here that does not follow the instructions, your issue might be closed,
locked, and assigned the `missing discussion` label.**
-->

## 🐛 Bug Report

Fastify through an error if the validation schema contains an enum without enforced type.

```
,{"type":"object","properties":{"monitor":{"type":"object","properties":{"status":{"enum":["ok","ko"]}},"required":["status"]}},"required":["monitor"]}
,FastifyError [Error]: Failed building the serialization schema for GET: /check/ready, due to error undefined unsupported
,    at Boot.<anonymous> (/project/node_modules/fastify/lib/route.js:271:19)
,    at /project/node_modules/avvio/boot.js:153:12
,    at Object.onceWrapper (events.js:416:28)
,    at Boot.emit (events.js:322:22)
,    at /project/node_modules/avvio/plugin.js:269:7
,    at done (/project/node_modules/avvio/plugin.js:201:5)
,    at check (/project/node_modules/avvio/plugin.js:225:9)
,    at internal/process/task_queues.js:153:7
,    at AsyncResource.runInAsyncScope (async_hooks.js:185:9)
,    at AsyncResource.runMicrotask (internal/process/task_queues.js:150:8) {
,  code: 'FST_ERR_SCH_SERIALIZATION_BUILD',
,  statusCode: 500
,}
```

## To Reproduce

1. add a route with this validation schema

```js
{
    schema: {
        response: {
            200: {
                type: 'object',
                properties: {
                    monitor: {
                        type: 'object',
                        properties: {status: {enum: ['ok', 'ko']}},
                        required: ['status'],
                    },
                },
                required: ['monitor'],
            },
        },
    },
}
```

## Expected behavior

no error at sever start

## Your Environment

- *node version*:  12.18.3
- *fastify version*: 3.1.1
- *os*: Linux
- *any other relevant information*

The only way to avoid this issue for now is to add a `type: string` along with the enum, but per [the spec](http://json-schema.org/understanding-json-schema/reference/generic.html#enumerated-values), `type` is optional and is set only to enforce a certain type along with the enum values. Enum can be mixed type.

This detail seems not that important, but it has a lot when combined to TypeScript and OpenAPI auto generated from the schema.  In this case `status` is shown as `string` instead of `enum` in TypeScript and documentation just to make the schema works for fastify.
