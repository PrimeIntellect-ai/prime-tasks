`format_code_in_doc_comments` formats some long line comments to block comments
## Meta

- **rustfmt version**: `rustfmt 1.5.1-nightly (b44197ab 2022-09-05)`
- **Minimum reproducible repo**: <https://github.com/pan93412/rustfmt-format-code-in-doc-comments-issue-repro-220906>
- **rustfmt configuration**:
  ```toml
  format_code_in_doc_comments = true
  ```

## Description

After enabling `format_code_in_doc_comments`, rustfmt formats the following line comments to block comments – which is neither a documented nor an expected behavior.

```rust
struct TestStruct {
    position_currency: String, // Currency for position of this contract. If not null, 1 contract = 1 positionCurrency.
    pu: Option<i64>, // Previous event update sequense ("u" of previous message), -1 also means None
}
```

## Expectation

`rustfmt` should not touch this.

```rust
struct TestStruct {
    position_currency: String, // Currency for position of this contract. If not null, 1 contract = 1 positionCurrency.
    pu: Option<i64>, // Previous event update sequense ("u" of previous message), -1 also means None
}
```

## Actual Result

```rust
struct TestStruct {
    position_currency: String, /* Currency for position of this contract. If not null, 1 contract = 1 positionCurrency. */
    pu: Option<i64>, /* Previous event update sequense ("u" of previous message), -1 also means None */
}
```

## Screenshot

![rustfmt with `format_code_in_doc_comments` changes the long comments to block comments](https://user-images.githubusercontent.com/28441561/188550268-b16b2b97-e061-4f18-83cf-606e84c0b864.png)

## Related

#3348
