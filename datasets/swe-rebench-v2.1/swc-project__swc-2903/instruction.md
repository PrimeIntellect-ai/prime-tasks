Issue parsing arrow function expression return types
**Describe the bug**

The parser seems to have issues with arrow function expression return types.

**Input code**

Examples:

```ts
Array(5).fill(0).map((_, i): true => {
    return true
});
```

```ts
Array(5).fill(0).map((_, i): ({ loading: false }) => ({
    loading: false,
}));
```

https://swc.rs/repl#%7B%22rawCode%22%3A%22Array(5).fill(0).map((_%2C%20i)%3A%20(%7B%20loading%3A%20false%20%7D)%20%3D%3E%20(%7B%5Cn%20%20%20%20loading%3A%20false%2C%5Cn%7D))%3B%22%2C%22rawConfig%22%3A%22%7B%7D%22%7D

**Expected behavior**

It parses.

**Version**

swc_ecmascript 0.57, but I see it happening still in the playground in the above link.

### Additional contract requirements

- An arrow function whose return type is written in parentheses, such as `(_, i): ({ loading: false }) => ...`, must parse, and the syntax tree must keep that return type as a parenthesized type node, the same way the parser represents any other parenthesized type.
