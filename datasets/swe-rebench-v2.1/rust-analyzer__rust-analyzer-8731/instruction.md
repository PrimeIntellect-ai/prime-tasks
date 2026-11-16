No completion for enum variants through type alias
```rust
enum Enum {
    VariantA,
    VariantB
}

type Type = Enum;

fn main() {
    let x = Type::<|>;
}
```

We should get completions for the variants, but currently don't. Very annoying in hir_ty currently, since we have so many type aliases for Chalk enums there :sweat_smile: Type inference works otherwise for e.g. `Type::VariantA`, so this seems to be a completion problem (well, the actual problem is that a lot of this name resolution logic happens inside of type inference and can't be reused by completion right now).
