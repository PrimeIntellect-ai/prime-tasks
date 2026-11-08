`deepKeys` helper?
Hi, I've implemented this a couple of times but wondered whether there'd be any interest in including it in this library:

```ts
const obj = { foo: { bar: 1, baz: { 'a.b': 2 } } }

deepKeys(obj) // ['foo.bar', 'foo.baz.a\\.b']
```

Worth doing here because the `\\.` is a convention invented by dot-prop (as far as I'm aware), so it makes sense for `deepKeys` to return paths that `getProperty` will later understand.
