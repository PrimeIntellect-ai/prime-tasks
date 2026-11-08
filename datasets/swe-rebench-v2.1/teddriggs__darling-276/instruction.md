Syntax for expressing enums with mixed variants
Let's say I have the following:
```rust
#[derive(Debug, FromField)]
#[darling(attributes(my_attribute))]
struct StructFieldReceiver {
    ident: Option<syn::Ident>,
    vis: syn::Visibility,
    ty: syn::Type,
    name: String,
    sql_type: SqlType,
}

#[derive(Debug, FromMeta)]
#[darling(rename_all = "lowercase")]
enum SqlType {
// omitted variants
    BigInt, Int, SmallInt, TinyInt, Bit,
    Float(Option<u8>),
    Decimal{
        p: Option<u8>,
        s: Option<u8>
    },
// omitted variants
}
```
I can use the variants without type with `#[my_attribute(name = "name", sql_type = "int")]`, but I don't know the correct syntax for specifying the Float or Decimal variants. Could you please point me in the right direction?

### Additional contract requirements

- A newtype enum variant (a variant with exactly one unnamed field) may be selected using the word form: the variant's name supplied as a string value, for example `sql_type = "float"` for `Float(Option<u8>)`.
- The word form is accepted when the newtype field type provides a value for an omitted input. For example, `Float(Option<u8>)` selected with `sql_type = "float"` yields `Float(None)`.
- When the field type provides no value for an omitted input (for example a `String` field), the word form is rejected with an unsupported-format error.
- A struct variant (a variant with named fields) is selected using the list form: the variant name followed by its fields, for example `sql_type(decimal(p = 1, s = 2))` for `Decimal { p: Option<u8>, s: Option<u8> }`.
