0.12.1 only allow lower-case variable name in template
I don't know if I asked a stupid question, but I spend one day to find it ! my rust version is 1.74.0, I run it on my win11 and WSL ubuntu 22.04, see the same error below
```rust
use askama::Template;

#[derive(Template)]
#[template(path = "hello.html")]
struct HelloTemplate<'a> {
    nAme: &'a str,
}
fn main() {
    let hello = HelloTemplate { nAme: "world" };
    println!("{}", hello.render().unwrap());
}
```
```html
Hello, {{ nAme }}!
```
```toml
[package]
name = "hello"
version = "0.1.0"
edition = "2021"

[dependencies]
askama="0.12.1"
```
[xxx.DESKTOP-ABCDE12] ⮞ cargo run -p hello
   Compiling hello v0.1.0 (C:\xx\xx\xx\hello)
error[E0425]: cannot find value `nAme` in this scope
 --> hello\src\main.rs:3:10
  |
3 | #[derive(Template)]
  |          ^^^^^^^^
  |
  = note: this error originates in the derive macro `Template` (in Nightly builds, run with -Z macro-backtrace for more info)
help: you might have meant to use the available field
  |
3 | #[derive(self.Template)]
  |          +++++

For more information about this error, try `rustc --explain E0425`.
error: could not compile `hello` (bin "hello") due to previous error
