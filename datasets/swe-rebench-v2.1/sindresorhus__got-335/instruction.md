Support posting Arrays with json option
Eventhough it was mentioned in #174:

> I'm ok with also supporting an array

Arrays are not supported with the `json` option (because of `isPlainObject`) so this fails:
```js
got.post('example.com', {
  json: true,
  body: [1, 2, 3]
})
```
Could you use something like [HIDDEN] instead of [HIDDEN] or test both [HIDDEN]?

### Additional contract requirements

- When `json` is enabled, accept an array body and serialize it as JSON for the request.
