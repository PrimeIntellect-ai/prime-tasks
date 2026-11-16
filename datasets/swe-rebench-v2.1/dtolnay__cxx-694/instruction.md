let_cxx_string blocks async fn's Future from being Send
This error is wrong, std::string is fine to access from across threads.

```rust
use cxx::{let_cxx_string, CxxString};

async fn f() {
    let_cxx_string!(s = "...");

    async fn g(_: &CxxString) {}
    g(&s).await;
}

fn main() {
    fn assert_send(_: impl Send) {}
    assert_send(f());
}
```

```console
error: future cannot be sent between threads safely
  --> src/main.rs:12:5
   |
11 |     fn assert_send(_: impl Send) {}
   |                            ---- required by this bound in `assert_send`
12 |     assert_send(f());
   |     ^^^^^^^^^^^ future returned by `f` is not `Send`
   |
   = help: within `impl Future`, the trait `Send` is not implemented for `*const ()`
note: future is not `Send` as this value is used across an await
  --> src/main.rs:7:5
   |
4  |     let_cxx_string!(s = "...");
   |     --------------------------- has type `StackString` which is not `Send`
...
7  |     g(&s).await;
   |     ^^^^^^^^^^^ await occurs here, with `mut $var` maybe used later
8  | }
   | - `mut $var` is later dropped here
```
