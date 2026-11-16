Panic on hovering over type name with lifetime argument
When hovering over the name of a type with a lifetime parameter, a panic occurs and [this error](https://github.com/rust-lang/rust-analyzer/files/14781790/stderr.txt) is printed to stderr. VS Code shows a popup with a "Request textDocument/hover failed." message.

**rust-analyzer version**: 0.4.1899-standalone (4b33850c3 2024-03-26)

**rustc version**: rustc 1.79.0-nightly (47ecded35 2024-03-26)

**code snippet to reproduce**:
Create a new empty project, then paste the following snippet:
```rust
fn main() {
    println!("Hello, world!");
}

struct Pedro<'a> {
    hola: &'a str
}
```
Now hover your mouse over the word `Pedro` and the panic will occur.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"dfireBird"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- For the reproduced case, hovering over `Pedro` must produce exactly this hover output:

````text
*Pedro*

```rust
test
```

```rust
struct Pedro<'a>
```
````
