Generic parameter in `handlebars_helper` does not compile.
Because the `handlebars_helper` macro uses `$tt`, the macro fails to compile in the following case:

```rust
handlebars_helper!(date_helper: |dt: DateTime<Utc>| dt.format("%F"));
```

```
error: no rules expected the token `<`
   --> src/bin.rs:119:50
    |
119 |     handlebars_helper!(date_helper: |dt: DateTime<Utc>| dt.format("%R"));
    |                                                  ^ no rules expected this token in macro call
```
