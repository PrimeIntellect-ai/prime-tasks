Incorrect error message "no such flag" with valid option
Hi @pacak, thanks again for bpaf! I'm migrating some projects at work to it and ran into an incorrect error message which I've reduced to this case:

```rust
struct Args {
    a: u64,
    b: u64,
}

fn parser() -> OptionParser<Args> {
    let a = long("a").argument("a");
    let b = long("b").argument("b");
    construct!(Args { a, b }).to_options()
}
```

When run with arguments `--b 1` bpaf outputs ``no such flag: `--b`, did you mean `--a`?``

### Additional contract requirements

- Also, for the `Args` parser above, running with `--b 1` must produce an error containing `--a`. For a parser with required `-b` and `-a` options, running with only `-a` must produce an error containing `-b`. When `-a` is given `-2` as its argument, the error must contain the exact text `` `-a` requires an argument `N` ``. When `-a -c` is parsed with `-c` a valid switch and required positional `X` missing, the error must contain `X`.
