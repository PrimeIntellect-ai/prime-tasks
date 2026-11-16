Cannot combine flags and options when using short
When I specify short names for options and flags, i.e. `-l, -f, -v <ARG>` I can combine the _flag_ arguments as `-lf`. However it's not possible to also specify -v in that form, i.e. `-lfv <ARG>` is invalid.
While this will only be possible when there is zero or one value argument in the last position, it does not seem far fetched to expect this to work.

I assume this is a conflict with supporting `-lARG`:

> For short flags value can follow immediately: -fbar. (docs)

**Reporducer**

```rust
use bpaf::{Bpaf, Parser};

#[allow(dead_code)]
#[derive(Debug, Clone, Bpaf)]
struct Args {
    #[bpaf(short, long)]
    list: bool,

    #[bpaf(short, long)]
    force: bool,

    #[bpaf(short, long)]
    value: String,
}

fn main() {
    let parsed = args().run();

    println!("{parsed:?}");
}
```

```shell
# ✅ all separate
$ cargo run -q -- -l -f -v abc
Args { list: true, force: true, value: "abc" }

# ✅ flags combined
$ cargo run -q -- -lf -v abc
Args { list: true, force: true, value: "abc" }

# 💢 flags and option combined
$ cargo run -q -- -lfv abc
Error: expected --value=ARG, got -lfv. Pass --help for usage information

# 💢 weird error message when using '='
$ cargo run -q -- -lfv=abc
Error: expected --value=ARG, got fv=abc. Pass --help for usage information
```

### Additional contract requirements

- For a parser where `-a` is both a short flag and a short option-argument, receiving `-ahello` must produce exactly: `app supports `-a` as both an option and an option-argument, try to split `-ahello` into individual options
(-a -h ..) or use `-a=hello` syntax to disambiguate`. For a parser with short flag `-a` and command `hello`, receiving `-ahello` must produce exactly: `no such flag: `-ahello`, did you mean `hello`?`.
