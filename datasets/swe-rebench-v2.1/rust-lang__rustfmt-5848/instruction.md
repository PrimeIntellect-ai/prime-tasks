`feature(non_lifetime_binder)` syntax gets removed
the following code:
```rust
#![feature(non_lifetime_binders)]
#![allow(incomplete_features)]

trait Other<U: ?Sized> {}

trait Trait<U>
where
    for<T> U: Other<T> {}
```
when formatted is:
```rust
#![feature(non_lifetime_binders)]
#![allow(incomplete_features)]

trait Other<U: ?Sized> {}

trait Trait<U>
where
    U: Other<T>,
{
}
```
