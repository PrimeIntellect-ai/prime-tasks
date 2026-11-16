`arg` macro fails to accept quoted strings
### Please complete the following tasks

- [x] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [x] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Rust Version

rustc 1.84.0 (9fc6b4312 2025-01-07)

### Clap Version

clap = { version = "4.5.39", features = ["cargo"] }

### Minimal reproducible code

```rust
use clap::{arg};

fn main() {
//let a = arg!(config-file: --config <FILE>);
//             ^^^^^^ no rules expected this token in macro call
//let a = arg!("config-file": --config <FILE>);
//                          ^ no rules expected this token in macro call
//let a = arg!("configfile": --config <FILE>);
//                         ^ no rules expected this token in macro call
let a = arg!(configfile: --config <FILE>); // Works
println!("{a:#?}")
}
```


### Steps to reproduce the bug with the above code

`cargo run`

### Actual Behaviour

```rust
//let a = arg!(config-file: --config <FILE>);
//             ^^^^^^ no rules expected this token in macro call
//let a = arg!("config-file": --config <FILE>);
//                          ^ no rules expected this token in macro call
//let a = arg!("configfile": --config <FILE>);
//                         ^ no rules expected this token in macro call
```


### Expected Behaviour

No compilation errors.

### Additional Context

The [docs](https://docs.rs/clap/latest/clap/macro.arg.html) say:
>The name may be either a bare-word or a string, followed by a :, like name: or "name":.

### Debug Output

_No response_
