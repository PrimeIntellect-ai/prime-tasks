Maybe `BufMut` trait should be `unsafe`?
I was thinking that it's likely that some `unsafe` code will rely on properties of `BufMut`. More specifically:

* That `remaining_mut` returns correct value
* `bytes_mut` always returns the same slice (apart from `advance()`)
* `has_remaining_mut` returns correct value
* `bytes_vectored` fills the correct data

Thus, I'd suggest making the trait `unsafe` to specify that `unsafe` code might rely on those properties and the implementors must ensure they hold.
