ability to inspect a request before making the call
New feature that would allow the developer to inspect a request before being sent

```js
dataPoint.addEntities({
  'request:<entityId>': {
    params: {
      inspect: Boolean|Function
    }
  }
})
```

If `params.inspect` is `true` it will output the entity's information to the console.

If `params.inspect` is a `function`, you may execute custom debugging code to be executed before the actual request gets made. The function receives the current accumulator value as its only parameter.

### Additional contract requirements

- Add a public function `inspect(acc, options)` in module `lib/entity-types/entity-request/reducer.js`.
- Add a public function `inspect(acc, data)` in module `lib/utils/index.js`.
- The inspection output written to `console.info` includes the entity id (`acc.reducer.spec.id`).
- The standard `console.info` call arguments must include the exact label `'\noptions:'` for options data and include each supplied key as `'\n<key>:'` followed by its JSON-stringified value (for example, `{ foo: 'bar' }` includes `'\nfoo:'` and `'"bar"'`). When `acc.params.inspect` is a function, the next `console.info` call must include the exact label `'\ncustom:'` before the function is invoked.
