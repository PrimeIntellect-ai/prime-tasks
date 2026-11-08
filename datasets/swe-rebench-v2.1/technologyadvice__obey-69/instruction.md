'default' validator doesn't work for booleans
Specifically when the default is `true`, but the record's value is `false`:
```
obey.model({
  enabled: { type: 'boolean', default: true }
})

// then elsewhere
validate({ enabled: false }) ==> { enabled: true }
```
[HIDDEN]

### Additional contract requirements

- For a boolean field with a default of `true`, preserve a supplied `false` value instead of replacing it with the default.
- For a number field with a default, preserve a supplied `0` value instead of replacing it with the default.
