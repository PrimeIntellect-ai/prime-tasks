Fallback handling of negative integer literals is different to proc_macro
This crate's fallback implementation of `From<TokenTree>` for `TokenStream` treats negative integer literals as one token, however `rustc`'s implementation treats negative integer literals as an alone `-` followed by the positive integer literal.

### How to Reproduce

1. Make a simple proc-macro crate, with this code:
```rust
use std::iter;
use proc_macro2::{TokenStream, TokenTree, Literal};

#[proc_macro]
pub fn proc_macro_test(input: proc_macro::TokenStream) -> proc_macro::TokenStream {
    //proc_macro2::fallback::force();

    let int: i32 = -3;
    let mut tokens = TokenStream::new();
    tokens.extend(iter::once(TokenTree::Literal(Literal::i32_suffixed(int))));
    dbg!(&tokens);

    input
}
```
2. Run that proc macro in another crate. With the commented line commented it will output two separate tokens, but with it uncommented it will output one negative literal token.
