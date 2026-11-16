oneOf with Date results to null
<!--
Before you submit an issue we recommend you visit [Fastify Help](https://github.com/fastify/help) and ask any questions you have or mention any problems you've had getting started with Fastify.

**Please read this entire template before posting any issue. If you ignore these instructions
and post an issue here that does not follow the instructions, your issue might be closed,
locked, and assigned the `missing discussion` label.**
-->

## 🐛 Bug Report

`oneOf` with `"format": "date-time"` string results to `null` when given a native `Date` object

## To Reproduce

```js
test('object with field of type string with format or null', (t) => {
  t.plan(2)

  const toStringify = new Date()

  const withoutOneOfSchema = {
    type: 'object',
    properties: {
      prop: {
        type: 'string',
        format: 'date-time'
      }
    }
  }

  const withoutOneOfStringify = build(withoutOneOfSchema)

  t.equal(withoutOneOfStringify({
    prop: toStringify
  }), `{"prop":"${toStringify.toISOString()}"}`)

  const withOneOfSchema = {
    type: 'object',
    properties: {
      prop: {
        oneOf: [{
          type: 'string',
          format: 'date-time'
        }, {
          type: 'null'
        }]
      }
    }
  }

  const withOneOfStringify = build(withOneOfSchema)

  // This fails, is really {"prop":null}

  t.equal(withOneOfStringify({
    prop: toStringify
  }), `{"prop":"${toStringify.toISOString()}"}`)
})
```

## Expected behavior

Test above includes expected behavior too

## Your Environment

- *node version*: 14
- *fastify version*: 3.14.2
- *os*: Mac
- Test above run with `master` branch of this repository

### Additional contract requirements

The same behaviour is required for the `anyOf` composition keyword as for `oneOf`. For a property schema of the form `{ anyOf: [{ type: 'string', format: <format> }, { type: 'null' }] }`, a native `Date` value must be serialized according to its format rather than producing `null`.

The supported string formats and the required serialization of a native `Date` are:

- `date-time`: the ISO 8601 string, i.e. `Date.prototype.toISOString()`.
- `date`: the local calendar date in `YYYY-MM-DD` form.
- `time`: the local wall-clock time in `HH:mm:ss` form.

A string value supplied for a `date-time`, `date`, or `time` format is validated against that format: a valid string is serialized unchanged, and an invalid string causes an error to be thrown.
