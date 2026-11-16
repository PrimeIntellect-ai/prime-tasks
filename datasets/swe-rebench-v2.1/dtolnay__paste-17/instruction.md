Identifier case conversion
Use case provided to me by email:

```rust
macro_rules! ld_r16_expr {
    ($($reg:ident)*) => {
        $(
            paste::item! {
                pub fn [<ld_ $reg _expr>] (val: Expr) -> Token {
                    token_for_opcode_two_args(
                        Mnemonic::Ld,
                        Register16::$reg.into(),
                        val.into(),
                    )
                }
            }
        )*
    }
}

ld_r16_expr!(Af Bc De Hl);
```

We would like some way to end up with functions `ld_af_expr` `ld_bc_expr` etc rather than `ld_Af_expr` `ld_Bc_expr`.

I would be be prepared to consider a PR implementing this as something like `[<ld_ $reg:lower _expr>]`.

### Additional contract requirements

- The identifier case-conversion modifier is spelled `:lower`, so `[<ld_ $reg:lower _expr>]` with `$reg` bound to `Af` produces a function named `ld_af_expr`.
- Inside a paste interpolation, `[<$id:lower>]` produces the identifier `$id` with all characters converted to lowercase (for example `Test` becomes `test`).
