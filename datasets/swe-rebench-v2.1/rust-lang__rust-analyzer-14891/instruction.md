[BUG] Const generics broken when inside struct
### Versions:
**rust-analyzer version**: 2023-05-15 & [Nightly](https://github.com/rust-lang/rust-analyzer/commit/0a806fe7ad28efa2de22ed3c9d3233cd1ed08dd1)

**rustc version**: 1.69.0

**relevant settings**: https://github.com/utkarshgupta137/nvim-lazy/blob/main/lua/lvim/lsp/settings/rust_analyzer.lua

### Minimal reproduction:
```rust
pub const ONE: usize = 1;

pub struct Inner<const P: usize>();

pub struct Outer {
    pub inner: Inner<ONE>,
}

fn main() {
    _ = Outer {
        inner: Inner::<1>(), // Error: expected Inner<ONE>, found Inner<1> | rust-analyzer (type-mismatch) [11, 16]
    };
}
```

### Diagnosis:
The bug doesn't exist in the 2023-05-08 release.
This PR included in the 2023-05-15 release seems relevant: https://github.com/rust-lang/rust-analyzer/pull/14727
