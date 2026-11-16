CxxVector::pop
We should expose functionality analogous to https://doc.rust-lang.org/std/vec/struct.Vec.html#method.pop on the Rust `CxxVector`.

This issues is split out from #778.

### Additional contract requirements

- Add a public method `CxxVector::<T>::pop(self: Pin<&mut Self>) -> Option<T>` on the Rust `CxxVector`, callable as `vector.pin_mut().pop()`.
- When the vector is empty, `pop` returns `None`.
