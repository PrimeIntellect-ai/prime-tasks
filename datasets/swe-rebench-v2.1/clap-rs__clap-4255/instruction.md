[clap_mangen] Subcommand references in man pages miss prefix
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Rust Version

rustc 1.63.0 (4b91a6ea7 2022-08-08)

### Clap Version

v3.2.22 (clap_mangen v0.1.11)

### Minimal reproducible code

```rust
#[derive(Parser)]
#[clap(about, author, version)]
struct Opt {
    #[clap(subcommand)]
    cmd: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    Check {
        file: PathBuf,
    },
    Manpages {
        dir: PathBuf,
    },
    #[clap(subcommand)]
    Temp(TempCommand),
}

#[derive(Subcommand)]
enum TempCommand {
    TestA,
    TestB,
}
```


### Steps to reproduce the bug with the above code

Create a dir `temp` in the current pwd and run a basic app with the above setup with `cargo run -- manpages temp`. As implementation for creating the manpages I use the below code:

```rust
fn print_manpages(dir: &Path) -> Result<()> {
    fn print(dir: &Path, app: &App) -> Result<()> {
        // `get_display_name()` is `Some` for all instances, except the root.
        let name = app.get_display_name().unwrap_or_else(|| app.get_name());
        let mut out = File::create(dir.join(format!("{name}.1")))?;

        clap_mangen::Man::new(app.clone()).render(&mut out)?;
        out.flush()?;

        for sub in app.get_subcommands() {
            print(dir, sub)?;
        }

        Ok(())
    }

    let mut app = Opt::command();
    app.build();

    print(dir, &app)
}
```

### Actual Behaviour

In the end of the man pages, the direct subcommands are listed as additional man page files. The sum of all these references are as follows:


- `sample-check(1)`
- `sample-manpages(1)`
- `sample-temp(1)`
- `temp-test-a(1)` <-- missing sample- prefix
- `temp-test-b(1)` <-- missing sample- prefix


### Expected Behaviour

As seen above, the last two references miss the expected prefix. The actual existing file name is right, but the names inside the man pages are wrong. The expected names would be:


- `sample(1)`
- `sample-check(1)`
- `sample-manpages(1)`
- `sample-temp(1)`
- `sample-temp-test-a(1)`
- `sample-temp-test-b(1)`


### Additional Context

Originally mentioned in discussion https://github.com/clap-rs/clap/discussions/3603, now extracted here as issue.

### Debug Output

_No response_
