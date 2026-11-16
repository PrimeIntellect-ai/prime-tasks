Regression with unification within fn (?)
See https://github.com/rust-analyzer/rust-analyzer/issues/6628.

I've got this down to the following Chalk test:
```rust
#[test]
fn ambiguous_unification_in_fn() {
    test! {
        program {
            trait FnOnce<Args> {
                type Output;
            }

            struct MyClosure<T> {}
            impl<T> FnOnce<(T,)> for MyClosure<fn(T) -> ()> {
                type Output = ();
            }
        }
        goal {
            exists<int T, U> {
                MyClosure<fn(&'static U) -> ()>: FnOnce<(&'static T,)>
            }
        } yields {
            "Unique"
        }
    }
}
```

This succeeded before #609 and now fails with an ambiguous result.

CC @jackh726  @daboross
