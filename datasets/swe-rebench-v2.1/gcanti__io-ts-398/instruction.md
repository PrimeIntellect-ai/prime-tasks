intersections don't play well with exact
## 🐛 Bug report

### Reproducible example

```ts
const C = t.intersection([t.exact(t.type({})), t.exact(t.partial({ a: t.number }))])
assert.deepStrictEqual(C.decode({ a: 1 }), right({ a: 1 }))
assert.deepStrictEqual(C.decode({ a: 1, b: 1 }), right({ a: 1 }))
```

### Additional context

RE: https://github.com/gcanti/io-ts/pull/390

### Your environment

| Software   | Version(s) |
| ---------- | ---------- |
| io-ts      |  2.0.1          |
| fp-ts      |  2.0.0          |
| TypeScript |  3.7.2          |
