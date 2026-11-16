Stringify fails with multiple defaults
<!--
Before you submit an issue we recommend you visit [Fastify Help](https://github.com/fastify/help) and ask any questions you have or mention any problems you've had getting started with Fastify.

**Please read this entire template before posting any issue. If you ignore these instructions
and post an issue here that does not follow the instructions, your issue might be closed,
locked, and assigned the `missing discussion` label.**
-->

## 🐛 Bug Report

Stringifying fails when using multiple defaults + required.  This isn't the case when using AJV directly.
You can run it here: https://repl.it/@gabemeola/fast-json-stringify-default-issue

Removing `required` passes but isn't the intended schema.
Removing all but one `default` and `required` does pass as intended.
e.g.
```
const schema = {
  type: 'object',
  properties: {
    name: {
      default: 'Person',
      type: 'string',
    },
  },
  required: [
    'name',
  ]
}

```

## To Reproduce

Steps to reproduce the behavior:

```js
const fastJson = require('fast-json-stringify')
const Ajv =  require('ajv')

const ajv = new Ajv({ useDefaults: true });

const schema = {
  type: 'object',
  properties: {
    name: {
      default: 'Person',
      type: 'string',
    },
    dev: {
      type: 'boolean',
      default: false,
    }
  },
  required: [
    'name',
    'dev'
  ]
}

const validate = ajv.compile(schema);
const str = fastJson(schema)

console.log("AJV Passed:", validate({}))
console.log(str({})) // Error: "name" is required!
```

## Expected behavior

A clear and concise description of what you expected to happen.

```js
{ "name": "Person", "dev": false }
```

## Your Environment

- *node version*: 12
- *fastify version*: 2.2.3
