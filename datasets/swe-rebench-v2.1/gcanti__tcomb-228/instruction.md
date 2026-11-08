null Maybes stringify to {}
Hello, something changed between 3.2.4 and 3.2.5 that causes this undesirable behavior

### Expected behaviour

```
const thing = t.struct({ foo: t.maybe(t.struct({ bar: t.String })) })
> JSON.stringify(thing({foo: null}))
'{"foo":null}'
```

### Actual behaviour

```
> JSON.stringify(thing({foo: null}))
'{"foo":{}}'
```

### Additional contract requirements

- When `foo` is `undefined`, `JSON.stringify(thing({foo: undefined}))` must produce `'{}'`.
