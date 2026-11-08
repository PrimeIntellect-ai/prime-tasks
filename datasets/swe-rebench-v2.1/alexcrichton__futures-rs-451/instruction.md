Stream::concat fails for empty streams
Hi!

`Stream::concat` seems to fail when the stream it is wrapping is empty (i.e. produces `Ready(None)` on the first poll).

To reproduce, compile and run this example:

```rust
extern crate futures;

use futures::{Future, Stream};

fn main() {
    let e = futures::stream::empty::<Vec<u8>, ()>();
    let mut c = e.concat();
    println!("Poll: {:?}", c.poll());
}
```

Result:

```
thread 'main' panicked at 'cannot poll Concat again', src/libcore/option.rs:705
stack backtrace:
   1:        0x10e381fff - std::sys::backtrace::tracing::imp::write::h6f1d53a70916b90d
   2:        0x10e383c1f - std::panicking::default_hook::{{closure}}::h137e876f7d3b5850
   3:        0x10e383126 - std::panicking::default_hook::h0ac3811ec7cee78c
   4:        0x10e3836cc - std::panicking::rust_panic_with_hook::hc303199e04562edf
   5:        0x10e383564 - std::panicking::begin_panic::h6ed03353807cf54d
   6:        0x10e383482 - std::panicking::begin_panic_fmt::hc321cece241bb2f5
   7:        0x10e3833e7 - rust_begin_unwind
   8:        0x10e3a7870 - core::panicking::panic_fmt::h27224b181f9f037f
   9:        0x10e3a78dd - core::option::expect_failed::h8606bc228cd3f504
  10:        0x10e379353 - <core::option::Option<T>>::expect::h78e9cd75a38fc6ae
  11:        0x10e37b6e4 - futures::stream::concat::expect::hcbba6ade024283b3
  12:        0x10e37ba5a - <futures::stream::concat::Concat<S> as futures::future::Future>::poll::h1c1ca2be81aca657
  13:        0x10e37c04f - rust_repro_futures_concat_empty_bug::main::ha26b06194c09e10f
  14:        0x10e38423a - __rust_maybe_catch_panic
  15:        0x10e382c3e - std::rt::lang_start::h538f8960e7644c80
  16:        0x10e37c189 - main
```

Expected behaviour:

`Concat<S>` implements `Future<Item=Option<S::Item>, Error=S::Error>`, to make it clear what  happens when the stream is empty and allow the user to statically verify that the case is handled.

If it's not an option to break the API, I would like it if at least this behaviour would be more clearly documented, and produces an error message that is more helpful in debugging the problem. Maybe we can also introduce a `concat_option` (or similar) method to provide a safer interface.

BTW I'd be excited to take on fixing this problem as my first contribution to `futures`.

### Additional contract requirements

The empty-stream case is fixed by adding a new stream combinator while keeping the
existing `Stream::concat` method available:

- Add a public method `Stream::concat2(self) -> Concat2<Self>` on the `Stream`
  trait, available when `Self: Sized` and
  `Self::Item: Extend<<Self::Item as IntoIterator>::Item> + IntoIterator + Default`.
  It returns a future that concatenates all items of the stream into the first
  item, extending that item with the contents of the remaining items. When the
  stream is empty, the future resolves to `Default::default()` for `Self::Item`.
  If the stream yields an error, the future resolves to that error.
- Add a public type `Concat2<S>` in the `futures::stream` module (re-exported
  alongside `Concat`). `Concat2<S>` implements `Future` with `Item = S::Item`
  and `Error = S::Error`.
