Support ident modifiers in doc
Currently, the following is not possible:

```rust
macro_rules! method {
    ($method:ident) => {
	#[doc = " Define an endpoint with path that allows only `" $method:snake:upper "` HTTP method"]
	pub fn $method() {}
    }
}
```

I looked into implementing it and send a PR but it looks like the `doc.rs` code is not using anything from `lib.rs`. I could have just copied the modifier code, but it felt like a hack reducing code quality. So, here I am creating an issue.
