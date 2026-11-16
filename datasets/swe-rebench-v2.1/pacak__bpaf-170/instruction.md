many + env = problem
```rust
#[test]
fn many_env() {
    std::env::set_var("USER", "top s3cr3t");
    let parser = short('v')
        .env("USER")
        .argument::<String>("USER")
        .many()
        .to_options();
    let r = parser.run_inner(Args::from(&[])).unwrap();
    todo!("{:?}", r);
}
```

### Additional contract requirements

When a parser used with `.many()` obtains a value from an environment variable without consuming any command-line arguments, the result must contain that environment-provided value once, and parsing must terminate.
