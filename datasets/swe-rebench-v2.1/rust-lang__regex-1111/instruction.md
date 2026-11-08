broadening of reverse suffix optimization has led to incorrect matches
Specifically, this program succeeds in `regex 1.9.x` but fails in `regex 1.10.1`:

```rust
fn main() -> anyhow::Result<()> {
    let re = regex::Regex::new(r"(\\N\{[^}]+})|([{}])").unwrap();
    let hay = r#"hiya \N{snowman} bye"#;
    let matches = re.find_iter(hay).map(|m| m.range()).collect::<Vec<_>>();
    assert_eq!(matches, vec![5..16]);
    Ok(())
}
```

Its output with `1.10.1`:

```
$ cargo run -q
thread 'main' panicked at main.rs:7:5:
assertion `left == right` failed
  left: [7..8, 15..16]
 right: [5..16]
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

I believe the issue here was my change to broaden the reverse suffix optimization to use one of many possible literals. But this turns out to be not be quite correct since the rules that govern prefixes don't apply to suffixes. [HIDDEN] But this winds up missing the match that came before it with the first alternate since the `{` isn't a suffix of the first alternate.

[HIDDEN]

Thank you to @charliermarsh for finding this! See: https://github.com/astral-sh/ruff/pull/7980

### Additional contract requirements

- For the pattern and haystack shown, iteration must yield only the match range `5..16`; a later match from one alternative must not cause an earlier valid match from another alternative to be skipped.
