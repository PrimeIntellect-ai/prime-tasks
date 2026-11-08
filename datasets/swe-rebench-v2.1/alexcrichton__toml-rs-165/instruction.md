Deserializing enums
I want to deserialize enum from string, I've seen many people already filed this issue but I am looking for quick solution.

```Rust
#[derive(Deserialize)]
enum Type {
    One,
    Two,
}
```

The error I'm getting:

```Rust
Error {
    inner: ErrorInner {
        kind: Custom,
        line: None,
        col: 0,
        message: "invalid type: string \"One\", expected enum Type",
        key: ["markets"],
    },
}
```

Is it possible to deserialize enum like that? Is there any quick solution to this without rewriting the parser?
I suppose it requires a lot of work if it hasn't been done for such a long time, or maybe it just wasn't worth the time or maybe there is a way to do this without too much effort?
