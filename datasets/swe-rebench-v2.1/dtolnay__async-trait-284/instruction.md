Unable to call `Self` in blanket implementation
I think this is a bug, sorry if it's not.

### Problem

When creating a blanket impl, e.g. `impl<T: A> B for T`, if you trying to call a `fn` on `Self` it doesn't work:

```rs
use async_trait::async_trait;

#[async_trait]
trait A {
    async fn a();
}

trait B {
    fn b();
}

#[async_trait]
impl<T: B> A for T {
    async fn a() {
        Self::b();
    }
}
```

```
error[E0276]: impl has stricter requirements than trait
  --> src/lib.rs:12:1
   |
5  |     async fn a();
   |     ------------- definition of `a` from trait
...
12 | #[async_trait]
   | ^^^^^^^^^^^^^^ impl has extra requirement `T: 'async_trait`
   |
   = note: this error originates in the attribute macro `async_trait` (in Nightly builds, run with -Z macro-backtrace for more info)
```

Same problem even if `B` has `#[async_trait]` (with or without `B::b()` being `async`).

### Expected

I feel like this should work because it works when not using `async`:

```rs
trait A {
    fn a();
}

trait B {
    fn b();
}

impl<T: B> A for T {
    fn a() {
        Self::b();
    }
}
```

### Workaround

I did figure out a workaround (halfway through writing this :sweat_smile:), which is to use `T` instead of `Self`, so I don't think this issue is high priority, but I figured I should still report it (and share the workaround).

```rs
use async_trait::async_trait;

#[async_trait]
trait A {
    async fn a();
}

trait B {
    fn b();
}

#[async_trait]
impl<T: B> A for T {
    async fn a() {
        T::b();
    }
}
```
