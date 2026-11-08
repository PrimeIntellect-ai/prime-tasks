Derive macro breaks on types with `'a` lifetime parameters
```rust
#[derive(Debug, Diagnostic, Error)]
#[error("foo")]
#[diagnostic(help("foo"))]
enum Foo<'a> {
    Bar {
        bar: &'a str
    }
}
```

Gives the following error at compile time

```
error[E0496]: lifetime name `'a` shadows a lifetime name that is already in scope
   --> tests/derive.rs:611:21
    |
611 |     #[derive(Debug, Diagnostic, Error)]
    |                     ^^^^^^^^^^ lifetime `'a` already in scope
...
614 |     enum Foo<'a> {
    |              -- first declared here
    |
    = note: this error originates in the derive macro `Diagnostic` (in Nightly builds, run with -Z macro-backtrace for more info)

error[E0308]: method not compatible with trait
   --> tests/derive.rs:611:21
    |
611 |     #[derive(Debug, Diagnostic, Error)]
    |                     ^^^^^^^^^^ lifetime mismatch
    |
    = note: expected fn pointer `fn(&'a enum_lifetime_parameter::Foo<'a>) -> Option<Box<(dyn std::fmt::Display + 'a)>>`
               found fn pointer `fn(&'a enum_lifetime_parameter::Foo<'a>) -> Option<Box<(dyn std::fmt::Display + 'a)>>`
note: the lifetime `'a` as defined here...
   --> tests/derive.rs:611:21
    |
611 |     #[derive(Debug, Diagnostic, Error)]
    |                     ^^^^^^^^^^
note: ...does not necessarily outlive the lifetime `'a` as defined here
   --> tests/derive.rs:614:14
    |
614 |     enum Foo<'a> {
    |              ^^
    = note: this error originates in the derive macro `Diagnostic` (in Nightly builds, run with -Z macro-backtrace for more info)
```

[HIDDEN]

I tried a first pass at fixing this myself, but didn't get far. [HIDDEN] I had trouble implementing the fully generic solution though, since I'm not very familiar with this part of the codebase.

### Additional contract requirements

- `#[derive(Diagnostic)]` must work for structs and enums with user-declared lifetime parameters, including fields that borrow through those lifetimes, without lifetime-shadowing or method-signature lifetime incompatibility errors.
