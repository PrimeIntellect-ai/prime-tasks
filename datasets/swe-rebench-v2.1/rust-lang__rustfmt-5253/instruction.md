`imports_granularity = "Module"` causes compile error when path contains `self`
**Describe the bug**

If a path contains `self`, this keyword must be enclosed in braces:

```rust
use crate::lexer::{self}; // valid
use crate::lexer::self;   // invalid
```

rustfmt with `imports_granularity = "Module"` sometimes splits `use` statements so that invalid code like above is emitted.

**To Reproduce**

```rust
use crate::lexer::{self, tokens::TokenData};
```

rustfmt formats it like this:

```rust
use crate::lexer::self;
use crate::lexer::tokens::TokenData;
```

When formatting the file again, the `::self` is removed.

**Expected behavior**

rustfmt should emit the following code without having to run it twice:

```rust
use crate::lexer;
use crate::lexer::tokens::TokenData;
```

Note that `use crate::lexer;` and `use crate::lexer::{self};` are not actually equivalent: The latter only imports the `lexer` module, while the former looks in all namespaces, so it can import up to 3 items at once, e.g. a function, a module and a macro of the same name.

To make sure that the behaviour doesn't change, it needs to be formatted like so:

```rust
use crate::lexer::{self};
use crate::lexer::tokens::TokenData;
```

However, I would find this rather annoying, because of the way rust-analyzer handles auto-imports.

**Meta**

- rustfmt version: rustfmt 1.4.34-nightly (ea268b9 2021-01-28)
- From where did you install rustfmt?: rustup
- How do you run rustfmt: `cargo fmt`

### Additional contract requirements

When module-granularity formatting splits a grouped import containing an explicit `self`, preserve that import's semantics by emitting the module import as `::{self}`. Do not replace it with an unbraced path that may import same-named items from other namespaces. The formatted output must also be valid on the first formatting run.
