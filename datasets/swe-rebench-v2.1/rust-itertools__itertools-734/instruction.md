Support for `next_if` and `next_if_eq` on PeekNth
Currently the documentation for [`itertools::peek_nth`](https://docs.rs/itertools/0.11.0/itertools/fn.peek_nth.html) says:

> A drop-in replacement for [std::iter::Peekable](https://doc.rust-lang.org/nightly/core/iter/adapters/peekable/struct.Peekable.html) which adds a peek_nth method allowing the user to peek at a value several iterations forward without advancing the base iterator.

It is however not a drop-in replacement at the moment, since the methods [`next_if`](https://doc.rust-lang.org/nightly/core/iter/struct.Peekable.html#method.next_if) and [`next_if_eq`](https://doc.rust-lang.org/nightly/core/iter/struct.Peekable.html#method.next_if_eq) isn't implemented.
