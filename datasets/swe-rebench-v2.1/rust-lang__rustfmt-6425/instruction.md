Incorrectly strips r# prefix from labels
Rust playground: https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=051766b3584e787d3abab1d2f18424bb

The following code:

```rust
'r#if: {
  break 'r#if;
}
```

when run through either stable or nightly rustfmt will incorrectly be formatted into this:

```rust
'r#if: {
  break 'if;
}
```

which rustc will complain because `'if` is an invalid label name:

```rust
error: invalid label name `'if`
 --> src/main.rs:5:15
  |
5 |         break 'if;
  |               ^^^
```

Note that this still does occur if the label name is not a keyword:

```rust
'r#a: {
  break 'r#a;
}
```

is formatted into

```rust
'r#a: {
  break 'a;
}
```

However this does not cause an error.

Versions of `rustfmt` (from rust-playground)
```1.8.0-stable (2024-11-26 90b35a6239)```
and
```1.8.0-nightly (2024-11-30 7442931d49)```

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"sobatha"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->
