prefer formatting object keys as identifiers where possible
Right now this test fails because `a` gets quoted, although it is a valid identifier and the quotes could be omitted:

```rust
let value = hcl::value!({ foo = { a = "b", "with space" = "c" } });
let expected = "foo = {\n  a = \"b\"\n  \"with space\" = \"c\"\n}\n";
assert_eq!(hcl::to_string(&value).unwrap(), expected);
```

```
  left: `"foo = {\n  \"a\" = \"b\"\n  \"with space\" = \"c\"\n}\n"`
 right: `"foo = {\n  a = \"b\"\n  \"with space\" = \"c\"\n}\n"`
```

In formatted HCL, identifiers are used as object keys where possible. We could support this via a formatter options, e.g. `prefer_ident_keys` which is enabled by default, but can be disabled if desired.

### Additional contract requirements

- Add `FormatterBuilder::prefer_ident_keys(self, yes: bool) -> Self` in `src/format/mod.rs`. When `yes` is `true`, object keys that are valid HCL identifiers are emitted without quotes; when `yes` is `false`, object keys are quoted unless they are already an `ObjectKey::Identifier`.
- `prefer_ident_keys` is disabled by default, so the default formatter quotes string object keys. The example above shows the output produced when `prefer_ident_keys` is enabled.
