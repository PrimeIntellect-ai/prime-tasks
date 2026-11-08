'overflow evaluating the requirement' when deriving debug for item that contains itself
the following code fails to compile

```
#[derive(derive_more::Debug)]
struct Message {
    inner: Box<Message>,
}

fn main() {}
```

```
error[E0275]: overflow evaluating the requirement `Message: Debug`
 --> src/main.rs:1:10
  |
1 | #[derive(derive_more::Debug)]
  |          ^^^^^^^^^^^^^^^^^^
  |
  = note: required for `Box<Message>` to implement `Debug`
  = help: see issue #48214
  = note: this error originates in the derive macro `derive_more::Debug` (in Nightly builds, run with -Z macro-backtrace for more info)
```

the same error is reported with stuff like `Vec<Message>` and with enum instead of struct.

```
$ cargo --version --verbose
cargo 1.78.0 (54d8815d0 2024-03-26)
release: 1.78.0
commit-hash: 54d8815d04fa3816edc207bbc4dd36bf18014dbc
commit-date: 2024-03-26
host: x86_64-unknown-linux-gnu
libgit2: 1.7.2 (sys:0.18.2 vendored)
libcurl: 8.6.0-DEV (sys:0.4.72+curl-8.6.0 vendored ssl:OpenSSL/1.1.1w)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Arch Linux Rolling Release [64-bit]
$ cat Cargo.toml
[package]
name = "derive-more-debug"
version = "0.1.0"
edition = "2021"

[dependencies]
derive_more = { version = "1.0.0-beta.6", features = ["debug"] }
```

### Additional contract requirements

The same overflow must also be avoided for the `derive_more::Display` derive (and the other `Display`-like derives). Deriving `Display` for a type that transitively contains itself — for example through `Box<Self>`, `Option<Box<Self>>`, or `Vec<Self>` — must compile without an `E0275` overflow error, and must produce the output dictated by the declared format strings.

A `Display`-like bound must only be required for a field type when that field type contains one of the derive's type parameters. Field types that do not mention any type parameter must not require such a bound.

For example, with

```rust
#[derive(Display, Debug)]
#[display("{inner:?}")]
#[display(bounds(T: Display))]
struct OptionalBox<T> {
    inner: Option<Box<T>>,
}

#[derive(Display, Debug)]
#[display("{next}")]
struct ItemStruct {
    next: OptionalBox<ItemStruct>,
}
```

`format!("{}", ItemStruct { next: OptionalBox { inner: None } })` must equal `"Some(ItemStruct { next: OptionalBox { inner: None } })"`.
