Multiple use of the same import is detected as circular
Currently circular imports are defined as including each other. This is the test verifying that behavior:
```rust
fn circular_import() {
  Test::new()
    .justfile("import 'a'")
    .tree(tree! {
      a: "import 'b'",
      b: "import 'a'",
    })
    .status(EXIT_FAILURE)
    .stderr_regex(path_for_regex(
      "error: Import `.*/a` in `.*/b` is circular\n",
    ))
    .run();
}
```

However, multiple use of the same import is also detected as circular and I don't think that is correct (test passes, but shouldn't IMHO):

```rust
fn reused_import() {
  Test::new()
    .justfile(
      "
      import 'a'
      import 'b'
    ",
    )
    .tree(tree! {
      a: "import 'c'",
      b: "import 'c'",
      c: "",
    })
    .status(EXIT_FAILURE)
    .stderr_regex(path_for_regex(
      "error: Import `.*/c` in `.*/a` is circular\n",
    ))
    .run();
}
```
