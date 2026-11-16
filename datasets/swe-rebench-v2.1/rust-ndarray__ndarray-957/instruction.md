Panic in `windows` of a view with negative strides
Here's a simple example:

```rust
use ndarray::prelude::*;

fn main() {
    let array = Array2::<i32>::eye(3);

    let _ = array.windows((2, 2)); // ok
    let _ = array.slice(s![.., ..; -1]).windows((2, 2)); // panics
}
```

This works fine with 0.14, but 0.15 panics:

```
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: ShapeError/Unsupported: unsupported operation', /home/jistone/rust/ndarray/src/impl_raw_views.rs:81:58
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: core::result::unwrap_failed
   3: core::result::Result<T,E>::unwrap
             at /builddir/build/BUILD/rustc-1.51.0-src/library/core/src/result.rs:1037:23
   4: ndarray::impl_raw_views::<impl ndarray::ArrayBase<ndarray::RawViewRepr<*const A>,D>>::from_shape_ptr
             at ./src/impl_raw_views.rs:81:17
   5: ndarray::impl_views::constructors::<impl ndarray::ArrayBase<ndarray::ViewRepr<&A>,D>>::from_shape_ptr
             at ./src/impl_views/constructors.rs:109:9
   6: ndarray::iterators::windows::Windows<A,D>::new
             at ./src/iterators/windows.rs:44:23
   7: ndarray::impl_methods::<impl ndarray::ArrayBase<S,D>>::windows
             at ./src/impl_methods.rs:1191:9
   8: windows::main
             at ./examples/windows.rs:7:13
   9: core::ops::function::FnOnce::call_once
             at /builddir/build/BUILD/rustc-1.51.0-src/library/core/src/ops/function.rs:227:5
```

`git bisect` blames e6a4f105725655a03d53e93a22f877d749ef9bbb of #885, although it's possible the functionality was changed in a neighboring commit, since the test code I used isn't actually doing anything with the windows.
