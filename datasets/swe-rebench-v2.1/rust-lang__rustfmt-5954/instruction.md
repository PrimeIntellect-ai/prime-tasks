Non-idempotent rustfmt run, adding commas to comments
Consider this (minimized) code:
```rust
struct Tau {}
impl Tau where (): Clone //,
{
}
```

Every time you run `rustfmt foo.rs`, it adds another comma to that comment.

```console
$ cat foo.rs
struct Tau {}
impl Tau where (): Clone //,
{
}

$ for i in $(seq 1 10); do rustfmt foo.rs; wc -c foo.rs; done
48 foo.rs
49 foo.rs
50 foo.rs
51 foo.rs
52 foo.rs
53 foo.rs
54 foo.rs
55 foo.rs
56 foo.rs
57 foo.rs

$ cat foo.rs
struct Tau {}
impl Tau where (): Clone //,,,,,,,,,,,
{
}
```

Tested on multiple versions:
+ rustfmt 1.5.2-stable (eb26296 2023-08-03)
+ rustfmt 1.5.2-stable (90c54180 2023-05-31)
