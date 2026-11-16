Inferred type equivalent to
#145 added support for "equivalent to" assertions for type aliases. But what about values?

```ts
interface ABC { a: string; b: string; c: string; }
function foo(abc: ABC) {
  let k: keyof ABC;
  for (k in abc) {
    // ^? let k: keyof ABC (equivalent to "a" | "b" | "c")
  }
}
```

### Additional contract requirements

- A value assertion may carry an `(equivalent to <type>)` annotation, as in the example above. The checker verifies that the value's type is equivalent to `<type>`: the sample passes when the types are equivalent and fails when they are not.
