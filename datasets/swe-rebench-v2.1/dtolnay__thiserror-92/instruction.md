Macro triggers unused_qualifications lint
```rust
#![warn(unused_qualifications)]
use std::error::Error;
fn main() -> Result<(), Box<dyn Error>> {
    Ok(())
}
#[derive(Debug, thiserror::Error)]
#[error("err")]
pub struct MyError;
```
triggers this warning:
```console
warning: unnecessary qualification
 --> src\main.rs:8:1
  |
8 | pub struct MyError;
  | ^^^^^^^^^^^^^^^^^^
  |
note: the lint level is defined here
 --> src\main.rs:1:9
  |
1 | #![warn(unused_qualifications)]
  |         ^^^^^^^^^^^^^^^^^^^^^

warning: 1 warning emitted
```
