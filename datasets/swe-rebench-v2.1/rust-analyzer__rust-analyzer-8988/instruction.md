Go to implementations should work on trait functions.
Feature request: "Go to Implementations" should work on trait functions.

E.g.:

```
trait Tr {
    fn f();
}

struct S;

impl Tr for S {
    fn f() {
        println!("Hello, world!");
    }
}
```

"Go to Implementations" on the trait's `fn f();` should go to the implementation in `S`.
