Env elaborater doesn't handle canonically-bound vars correctly
```
#[test]
fn env_bound_vars() {
    test! {
        program {}
        goal {
            exists<'a> {
                if (WellFormed(&'a ())) {
                    WellFormed(&'a ())
                }
            }
        } yields {
            "Unique"
        }
        goal {
            exists<'a> {
                if (FromEnv(&'a ())) {
                    WellFormed(&'a ())
                }
            }
        } yields {
            "Unique"
        }
    }
}
````
currently gives this error:
```
thread 'test::misc::env_bound_vars' panicked at 'assertion failed: `(left == right)`
  left: `^1`,
 right: `^0`', <::std::macros::panic macros>:5:6
```
