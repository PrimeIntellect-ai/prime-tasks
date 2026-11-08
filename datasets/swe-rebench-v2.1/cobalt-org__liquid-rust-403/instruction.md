`split` of `Nil` should be empty array
Example test:
```rust
    assert_eq!(v!([]), filters!(split, Nil, v!(" ")));
```

- [Rust implementation](https://github.com/cobalt-org/liquid-rust/blob/master/src/filters/mod.rs)
- [Ruby implementation](https://github.com/Shopify/liquid/blob/master/lib/liquid/standardfilters.rb)
- [Relevant tests](https://github.com/cobalt-org/liquid-rust/search?q=liquid+263&unscoped_q=liquid+263)
  - Once this is working, ideally the test will start failing.  We would just need to remove the `#[should_panic]` on it
  - If the test doesn't start failing, please temporarily remove `#[should_panic]`, and find or create an issue for the new failure
