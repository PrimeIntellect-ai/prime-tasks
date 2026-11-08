Optionally ignore `toJSON`
`serialize-error` automatically uses `toJSON`:

https://github.com/sindresorhus/serialize-error/blob/855fe3dc67e0376070007d72ac5cf88bafdb7d36/index.js#L61-L63

Unfortunately this introduces two unwanted behaviors:

- code can be executed by passing `{toJSON() { /*h4xor*/ }}`
- serialization is decided by the object owner, with which we might disagree (e.g. it might [exclude arbitrary properties](https://github.com/pixiebrix/pixiebrix-extension/blob/22c2a0b3bae84c42253eb8adb97f5bed15d68cd3/src/services/errors.ts#L90-L92))

### Possible solution

```js
serializeError(error, {toJSON: false})
```

### Additional contract requirements

The opt-out option is named `useToJSON`. Passing `{useToJSON: false}` to `serializeError` prevents `.toJSON()` methods from being invoked on the supplied object and on objects nested at any depth. Those objects are serialized from their ordinary properties instead.
