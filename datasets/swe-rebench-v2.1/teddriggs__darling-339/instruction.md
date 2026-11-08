#[darling(with = "func")] string paths no longer work
In previous versions of darling (e.g. 0.20.10 and earlier), the following syntax was supported:
```
#[darling(with = "maybe_float_or_int")]
```
This worked by allowing string literals to represent function paths, which were parsed and treated as equivalent to:
```
#[darling(with = maybe_float_or_int)]
```
However, in darling 0.20.11, this syntax now fails with a type mismatch error:
```
> cargo c
    Checking playground v0.1.0 (/home/suika/code/suika/playground)
error: Unexpected type `lit`
 --> src/darling.rs:7:47
  |
7 |     #[darling(default, rename = "min", with = "maybe_float_or_int")]
  |                                               ^^^^^^^^^^^^^^^^^^^^

error: could not compile `playground` (bin "playground") due to 1 previous error
```

In PR [#310](https://github.com/TedDriggs/darling/pull/310), support for closures in #[darling(with = ...)] was added, but as part of the change, [HIDDEN], which breaks existing uses.

### Additional contract requirements

- A string literal naming a function path in `#[darling(with = ...)]` must be accepted and treated as equivalent to the corresponding unquoted function path.
