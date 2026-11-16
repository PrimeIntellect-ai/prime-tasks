Suport for-loop over `nil`
Related: #270

Example test:
```rust
    assert_template_result!(
        "-",
        "{%for item in array%}+{%else%}-{%endfor%}",
        v!({ "array": nil }),
    );
```

- [for-loop code](https://github.com/cobalt-org/liquid-rust/blob/master/src/tags/for_block.rs)
- [Ruby implementation](https://github.com/Shopify/liquid/blob/master/lib/liquid/tags/for.rb)
- [Relevant tests](https://github.com/cobalt-org/liquid-rust/search?q=liquid+294&unscoped_q=liquid+294)
  - Once this is working, ideally the test will start failing.  We would just need to remove the `#[should_panic]` on it
  - If the test doesn't start failing, please temporarily remove `#[should_panic]`, and find or create an issue for the new failure
