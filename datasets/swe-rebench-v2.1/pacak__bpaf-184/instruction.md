fallback for `some`
Currently it is possible to emulate `fallback` for for vectors of items using `map` and `parse`. Does it make sense to support this natively for `some`?

```rust
#[test]
fn default_for_many() {
    use bpaf;

    let roots = bpaf::positional::<String>("ROOTS").many().map(|items| {
        if items.is_empty() {
            vec![String::from(".")]
        } else {
            items
        }
    });

    struct Roots {
        roots: Vec<String>,
    }

    let r = construct!(Roots { roots })
        .to_options()
        .run_inner(Args::from(&[]));
    assert_eq!(vec![String::from(".")], r.unwrap().roots);
}
```

See https://github.com/pacak/bpaf/issues/79 for original question

### Additional contract requirements

- When a positional parser marked with `.some(msg)` receives no value, a downstream `.fallback_with(...)` must be able to supply a replacement value instead of parsing failing.
