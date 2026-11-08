Broken command aliases
Command aliases fail to parse (or I'm using them wrong?):

```rust
fn main() {
    groups().run();
}

#[derive(Debug, Bpaf, Clone)]
enum Groups {
    #[bpaf(command("top"), long("top-alias"))]
    Command(),
}
```

```
✅ $ cargo run -- top
💢 $ cargo run -- top-alias
Error: expected `COMMAND ...`, got `top-alias`. Pass `--help` for usage information
```
