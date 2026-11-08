`broken_link_callback` removed support for closures borrowing from their context
In https://github.com/kivikakk/comrak/pull/484 the change made the callback require `'static` lifetime, because `Arc` has an implicit `+ 'static` bound.

This means that closures which borrow from their environment are forbidden now, and must be made to own all of their state. This is especially difficult to use `comrak` in methods that take `&self` and need to call `self.some_lookup_method()` when fixing links.

The same problem still exists when implementing the `BrokenLinkCallback` trait, since `Arc<dyn BrokenLinkCallback>` is always going to require `'static` for every implementation.

[HIDDEN]

### Additional contract requirements

Options containing a broken-link callback must be usable for the lifetime of the callback's borrowed data. Neither a callback closure nor a user-defined callback implementation should need to own data that it can borrow from its surrounding context.
