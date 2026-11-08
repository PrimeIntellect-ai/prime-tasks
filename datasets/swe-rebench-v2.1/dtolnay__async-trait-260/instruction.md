Using async-trait with nightly-2024-03-04 triggers `unused-qualifications` lint
Consider the following code:

```rust
use async_trait::async_trait;  // async-trait = "0.1.77"

#[async_trait]
pub trait Foo {
    async fn foo(&self);
}

pub struct Bar;

#[async_trait]
impl Foo for Bar {
    async fn foo(&self) {
        todo!()
    }
}
```

with the following in `Cargo.toml`:

```toml
[lints.rust]
unused_qualifications = "deny"
```

Using the current nightly channel (d18480b84 2024-03-04), running `cargo +nightly check` on the above fails with:

```text
error: unnecessary qualification
 --> src/lib.rs:5:5
  |
5 |     async fn foo(&self);
  |     ^^^^^
  |
  = note: requested on the command line with `-D unused-qualifications`
help: remove the unnecessary path segments
  |
5 |     async fn foo(&self);
  |

error: unnecessary qualification
  --> src/lib.rs:12:5
   |
12 |     async fn foo(&self) {
   |     ^^^^^
   |
help: remove the unnecessary path segments
   |
12 |     async fn foo(&self) {
   |

error: could not compile `unused-qual` (lib) due to 2 previous errors
```
