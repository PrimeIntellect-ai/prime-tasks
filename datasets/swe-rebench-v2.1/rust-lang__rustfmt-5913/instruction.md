buggy formatting on expression attributes with comments
Example code:
```rs
#![feature(stmt_expr_attributes)]
fn main() {
    let some_function_call = || {};

    let filter = || {
        (
            // comment
            #[allow(clippy::disallowed_methods)]
            some_function_call()
        )
    };
}
```

Everytime you format it it replicates the attribute and doubles it:
```rs
#![feature(stmt_expr_attributes)]
fn main() {
    let some_function_call = || {};

    let filter = || {
        (
            // comment
            #[allow(clippy::disallowed_methods)]
            #[allow(clippy::disallowed_methods)]
            some_function_call()
        )
    };
}
```

Version: rustfmt 1.6.0-nightly (39f42ad9 2023-07-19)
