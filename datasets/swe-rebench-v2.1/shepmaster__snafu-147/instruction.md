`#[snafu(source, backtrace)]` fails to parse
```
error: expected parentheses
  --> tests/source_and_backtrace.rs:19:23
   |
19 |         #[snafu(source, backtrace)]
   |                       ^

```

In fact, I'd guess the same would happen with any type that parses using `MyParens`, when placed in a non-final slot in the list of attributes.

Found in #141, missed during fix of multiple attributes in #137.

### Additional contract requirements

- For invalid syntax such as `#[snafu(source(5))]`, the diagnostic message must be exactly `expected boolean literal or identifier`.
- For `#[snafu(source(5))]`, the diagnostic must point to the `5` token.
