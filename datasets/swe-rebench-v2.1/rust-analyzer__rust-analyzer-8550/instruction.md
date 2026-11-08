Extended key-value attributes result in broken macro expansion
cc https://github.com/rust-analyzer/rust-analyzer/issues/8092

```rust
macro_rules! enum_from_u32 {
    (pub enum $name:ident {
        $($(#[$var_attr:meta])* $variant:ident,)*
    }) => {
        pub enum $name {
            $($variant,)*
        }

        impl $name {}
    }
}

macro_rules! language_item_table {
    (
        $( $variant:ident )*
    ) => {
        enum_from_u32! {
            pub enum LangItem {
                $(
                    #[doc = concat!("The `", "bla", "` lang item.")]
                    ///
                    $variant,
                )*
            }
        }
    }
}

language_item_table! {
    Bool
}
```

Results in:

```rust
pub enum$name{}
impl$name{}
```

...which is parsed as a `name!` macro invocation, causing spurious "unresolved macro call" diagnostics
