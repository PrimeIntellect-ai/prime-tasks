`expand glob import` should expand to all possible items without filtering for `pub use` reexports.
**rust-analyzer version**:  `0.4.1255-standalone`
**rustc version**: `rustc 1.66.0-nightly (3f83906b3 2022-09-24)`

```rust
mod qqq {
    use super::*;

    pub trait Tr1{}
    pub trait Tr2{}
    pub struct St1{}
    pub struct St2{}
    pub enum En1{}
}

pub use qqq::┃*;
```

After "expand glob import", I expect.

```rust
mod qqq {
    use super::*;

    pub trait Tr1{}
    pub trait Tr2{}
    pub struct St1{}
    pub struct St2{}
    pub enum En1{}
}

pub use qqq::┃{Tr1, Tr2, St1, St2, En1};
```

but I get:


```rust
mod qqq {
    use super::*;

    pub trait Tr1{}
    pub trait Tr2{}
    pub struct St1{}
    pub struct St2{}
    pub enum En1{}
}

pub use qqq::┃{};
```

Unless RA is willing to analyse the whole workspace for which reexports are actually needed, I think it should just expand to everything. This would allow for easy gradual refactor by moving chunks of code to separate files without also having multiple glob imports one after another.

Alternatively, a second, simpler code assist "Expand glob import (all items)" can be added.

Workaround: Use Ctrl+Space, Enter, Comma, Ctrl+Space, Enter, Comma, ... repeatedly until it offers `self.`
