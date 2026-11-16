fix: forbidUnknownValues doesn't default to true when validatorOptions are undefined
### Description
0.14.0 is supposed to make `forbidUnknownValues` default to `true`. However, it only defaults to `true` when a `validatorOptions` object is passed.

**Minimal code-snippet showcasing the problem**
```ts
await validateOrReject({}); // resolves
await validateOrReject({}, {}); // rejects
```

### Expected behavior
`forbidUnknownValues` should default to `true` unless explicitly specified as `false`.

### Actual behavior
`forbidUnknownValues` continues to default to `false` when no `validatorOptions` object is specified.
