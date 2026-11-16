`toml` outputs negative numbers for large u64 values
For large u64 values, `tom::to_string` generates negative u64 numbers.

Code:
```rust
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize)]
pub struct Config {
    pub seed: u64,
}

fn main() {

    let cfg = Config {
        seed: 16237911273155533842,
    };
    println!("{}", toml::to_string(&cfg).unwrap());
}
```

Running it:
```bash
~/code/github/repro/repro-2 ❯ cargo run --release
   Compiling repro-2 v0.1.0 (/Users/maxime/Code/github/repro/repro-2)
    Finished release [optimized] target(s) in 0.78s
     Running `target/release/repro-2`
seed = -2208832800554017774

~/code/github/repro/repro-2 ❯ cargo run
   Compiling repro-2 v0.1.0 (/Users/maxime/Code/github/repro/repro-2)
    Finished dev [unoptimized + debuginfo] target(s) in 0.29s
     Running `target/debug/repro-2`
seed = -2208832800554017774
```


Rust version:
```bash
~/code/github/repro/repro-2 ❯ rustc --version
rustc 1.67.0 (fc594f156 2023-01-24)
~/code/github/repro/repro-2 ❯ cargo version
cargo 1.67.0 (8ecd4f20a 2023-01-10)
```


Crate versions:
```bash
~/code/github/repro/repro-2 ❯ cargo tree
repro-2 v0.1.0 (/Users/maxime/Code/github/repro/repro-2)
├── serde v1.0.152
│   └── serde_derive v1.0.152 (proc-macro)
│       ├── proc-macro2 v1.0.51
│       │   └── unicode-ident v1.0.6
│       ├── quote v1.0.23
│       │   └── proc-macro2 v1.0.51 (*)
│       └── syn v1.0.107
│           ├── proc-macro2 v1.0.51 (*)
│           ├── quote v1.0.23 (*)
│           └── unicode-ident v1.0.6
└── toml v0.7.1
    ├── serde v1.0.152 (*)
    ├── serde_spanned v0.6.1
    │   └── serde v1.0.152 (*)
    ├── toml_datetime v0.6.1
    │   └── serde v1.0.152 (*)
    └── toml_edit v0.19.2
        ├── indexmap v1.9.2
        │   └── hashbrown v0.12.3
        │   [build-dependencies]
        │   └── autocfg v1.1.0
        ├── nom8 v0.2.0
        │   └── memchr v2.5.0
        ├── serde v1.0.152 (*)
        ├── serde_spanned v0.6.1 (*)
        └── toml_datetime v0.6.1 (*)
```

Setup:
```
OS: macOS 13.2 22D49 arm64
Host: MacBookPro18,1
CPU: Apple M1 Pro
```


I am not able to reproduce this bug in the Rust Playground.

### Additional contract requirements

- `toml::to_string` returns `Err(toml::ser::Error)` for a `u64` value greater than `i64::MAX`, instead of emitting a negative number. For `u64::MAX` the error's display text is `out-of-range value for u64 type`.
- `toml::Table::try_from` returns `Err(toml::ser::Error)` for a `u64` value greater than `i64::MAX`. For `u64::MAX` the error's display text is `u64 value was too large`.
