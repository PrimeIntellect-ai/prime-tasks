Question: Default/Fallback for many/some?
Hello, first of all many thanks for this beautiful library!

I was wondering how I could achieve providing a calculated default for a `.many()` parser as demonstrated in the following test. (I also tried using `.some(..)` but that fails as well :/) Any ideas?

```rust
    #[test]
    fn default_positional() {
        use bpaf;

        let roots = bpaf::positional::<String>("ROOTS")
            .fallback_with::<_, String>(|| Ok(String::from(".")))
            .many();

        struct Roots { roots: Vec<String>, }

        let r = construct!(Roots {roots}).to_options().run_inner(Args::from(&[]));
        assert_eq!(vec![String::from(".")], r.unwrap().roots);
    }
```

### Additional contract requirements

- `pure_with(callback)` is a public parser constructor. It takes a zero-argument closure that returns `Result<T, E>`, where `E` can be converted to a string.
- When the callback returns `Ok(value)`, the parser succeeds with `value` and does not consume any command line arguments, so parsers placed before or after it in `construct!` still see the full input.
- When the callback returns `Err(e)`, the parser fails with an error whose message contains the text of `e`.
- A positional `.some(..)` parser combined with a `pure_with` parser in `construct!` yields the user-supplied values when any are given, and the callback's collection when none are given.
- When the callback fails, that alternative counts as failed, so the next alternative in `construct!([...])` is used.
