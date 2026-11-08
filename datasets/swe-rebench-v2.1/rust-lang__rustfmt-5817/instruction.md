skip_macro_invocations: Cannot configure from `rustfmt.toml`
`skip_macro_invocations` option doesn't parse as [documented](https://rust-lang.github.io/rustfmt/?version=master&search=macro#skip_macro_invocations).

Writing `skip_macro_invocations=["*", "println"]` in `rustfmt.toml` leads to this error:

```
Error: Decoding config file failed:
unknown variant `*`, expected `Name` or `All`
in `skip_macro_invocations`

Please check your config file.
```

It seems that parsing rules are not what is actually designed (`*` or some name), but more like tagged serde enum. These config files work:

```toml
[[skip_macro_invocations]]
Name="aboba"
```

```toml
skip_macro_invocations = ["All"]
```
