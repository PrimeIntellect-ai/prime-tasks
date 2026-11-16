Bad error message for a command that expects a positional argument
Exapmple code:
```rust
use bpaf::Parser;

#[derive(Debug, Clone)]
enum Opts {
    Opt { arg: String },
    Noopt,
}

fn main() {
    let command = bpaf::positional("NAME")
        .to_options()
        .descr("descr for command")
        .command("command")
        .help("help for command")
        .map(|arg| Opts::Opt{ arg });

    let noopt = bpaf::pure(Opts::Noopt);
    let run = bpaf::construct!([noopt]);

    let opts = bpaf::construct!([command, run])
        .to_options()
        .descr("top level descr")
        .run();

    match opts {
        Opts::Opt {arg} => println!("Opt {}", arg),
        Opts::Noopt => println!("Noopt"),
    }
}
```

Example invokation:
```
> ./target/debug/bpaf-test
Noopt
> ./target/debug/bpaf-test command foo
Opt foo
> ./target/debug/bpaf-test command
command is not expected in this context
>
```

"not expected in this context" is a confusing error message, since that command kind of is expected in this context. I think it should rather say something like "eof not expected in this context" or in the best case "expecting a positional argument NAME following 'command'"

### Additional contract requirements

When a command that expects a positional argument is invoked without that
argument, the reported error message must be exactly:

    Expected <NAME>, pass --help for usage information

where `<NAME>` is the name of the missing positional argument (for the example
above, the positional argument is named `NAME`).
