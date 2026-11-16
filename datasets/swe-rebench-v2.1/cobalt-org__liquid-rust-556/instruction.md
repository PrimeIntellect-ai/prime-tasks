parser: byte index 1 is not a char boundary
While fuzz testing parser, encountered following panic:

```rust
#[test]
fn test_fuzz() {
    if let Ok(_) = liquid::ParserBuilder::with_stdlib()
        .build()
        .unwrap()
        .parse("˄{%")
    {}
}
```

```sh
thread 'test_fuzz' panicked at crates/core/src/parser/parser.rs:659:70:
byte index 1 is not a char boundary; it is inside '˄' (bytes 0..2) of `˄{%`
stack backtrace:
```

Panicked at:
https://github.com/cobalt-org/liquid-rust/blob/8de2d34629fd387295312f2d625556ac40921bcc/crates/core/src/parser/parser.rs#L659

Crash input:
[crash-2dbc79c17b5c840978e94df8716233b7203e1e08.txt](https://github.com/user-attachments/files/16403759/crash-2dbc79c17b5c840978e94df8716233b7203e1e08.txt)



liquid-rust version: 0.26.8
rust version: 1.78.0
OS: Ubuntu 20.04.6 LTS

### Additional contract requirements

- For the input `˄{%`, parsing must return an error whose `to_string()` is exactly:

```
liquid:  --> 1:3
  |
1 | {%
  |   ^---
  |
  = expected Identifier

```
