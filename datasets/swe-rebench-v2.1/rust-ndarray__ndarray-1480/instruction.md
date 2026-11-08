`ArrayView` should be covariant over lifetime
Take a look at the following example:
```rust
fn reference_covariant<'a>(x: &'static f64) -> &'a f64 {
    x
}

fn arrayview_covariant<'a>(x: ArrayView1<'static, f64>) -> ArrayView1<'a, f64> {
    x
}
```

The first compiles fine, the second one does not compile and give the following error message:
```
fn arrayview_covariant<'a>(x: ArrayView1<'static, f64>) -> ArrayView1<'a, f64> {
                       -- lifetime `'a` defined here
   x
   ^ returning this value requires that `'a` must outlive `'static`

note: requirement occurs because of the type `ArrayBase<ViewRepr<&f64>, Dim<[usize; 1]>>`, which makes the generic argument `ViewRepr<&f64>` invariant
note: the struct `ArrayBase<S, D>` is invariant over the parameter `S`
```

The problem is caused by the usage of `S::Elem` inside the definition of `ArrayBase`.

I stumbled across this problem, since I used `ArrayView` deep inside a data structure which should be covariant.
As a user of ndarray I would assume that `ArrayView`s behave the same as Rust references, but I see fixing this bug is hard without interface changes.
Is there an easy work-around for such problems? I currently do not know of any...
