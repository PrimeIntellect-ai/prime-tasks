Generated man pages still claim that flag options take values
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Rust Version

rustc 1.64.0 (Fedora 1.64.0-1.fc36)

### Clap Version

4.0.18, clap_mangen 0.2.4

### Minimal reproducible code

```rust
use clap::{CommandFactory, Parser};

#[derive(Parser)]
/// Command to do things
pub struct Cmd {
    /// Do thing
    #[clap(long)]
    thing: bool,
}

fn main() {
    Cmd::parse();
    clap_mangen::Man::new(Cmd::command())
        .render(&mut std::io::stdout())
        .unwrap();
}
```

Cargo.toml:

```toml
[package]
name = "clap-man"
version = "0.0.0"
edition = "2021"

[dependencies]
clap = { version = "4", features = ["derive"] }
clap_mangen = "0.2"
```

### Steps to reproduce the bug with the above code

```command
cargo run | man -l -
```

### Actual Behaviour

The option description for `--thing` claims that it takes an argument:

```
clap-man(1)                 General Commands Manual                clap-man(1)

NAME
       clap-man - Command to do things

SYNOPSIS
       clap-man [--thing] [-h|--help]

DESCRIPTION
       Command to do things

OPTIONS
       --thing=THING
              Do thing

       -h, --help
              Print help information

                                   clap-man                        clap-man(1)
```

It doesn't:

```command
$ cargo run -- --thing=true
    Finished dev [unoptimized + debuginfo] target(s) in 0.04s
     Running `target/debug/clap-man --thing=true`
error: The value 'true' was provided to '--thing' but it wasn't expecting any more values

Usage: clap-man --thing

For more information try '--help'
```

### Expected Behaviour

The man page lists the option without any argument, as it did in clap 3.2 / clap_mangen 0.1:

```
clap-man(1)                 General Commands Manual                clap-man(1)

NAME
       clap-man - Command to do things

SYNOPSIS
       clap-man [--thing] [-h|--help]

DESCRIPTION
       Command to do things

OPTIONS
       --thing
              Do thing

       -h, --help
              Print help information

                                   clap-man                        clap-man(1)
```

### Additional Context

This is a followup to https://github.com/clap-rs/clap/issues/4410.  clap_mangen 0.2.4 improved the situation but didn't fix it.

### Debug Output

_No response_
