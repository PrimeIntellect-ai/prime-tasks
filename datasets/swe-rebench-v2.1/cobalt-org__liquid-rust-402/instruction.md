`truncate` has overflow problems
`thread 'conformance_ruby::standard_filter_test::test_truncate' panicked at 'attempt to subtract with overflow', src/filters/mod.rs:218:22`

- [Rust implementation](https://github.com/cobalt-org/liquid-rust/blob/master/src/filters/mod.rs)
- [Ruby implementation](https://github.com/Shopify/liquid/blob/master/lib/liquid/standardfilters.rb)
- [Relevant tests](https://github.com/cobalt-org/liquid-rust/search?q=liquid+264&unscoped_q=liquid+264)
  - Once this is working, ideally the test will start failing.  We would just need to remove the `#[should_panic]` on it
  - If the test doesn't start failing, please temporarily remove `#[should_panic]`, and find or create an issue for the new failure
