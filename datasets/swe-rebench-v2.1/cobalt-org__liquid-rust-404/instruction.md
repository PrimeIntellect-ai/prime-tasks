`divide_by` 0 should error
Example test:
```rust
    assert_render_error!("{{ 1.0 | divided_by: 0.0 | ceil }}");
```

Shopify:
```ruby
    assert_raises(Liquid::FloatDomainError) do
      assert_template_result "4", "{{ 1.0 | divided_by: 0.0 | ceil }}"
    end
```

- [Rust implementation](https://github.com/cobalt-org/liquid-rust/blob/master/src/filters/math.rs)
- [Ruby implementation](https://github.com/Shopify/liquid/blob/master/lib/liquid/standardfilters.rb)
- [Relevant tests](https://github.com/cobalt-org/liquid-rust/search?q=liquid+251&unscoped_q=liquid+251)
  - Once this is working, ideally the test will start failing.  We would just need to remove the `#[should_panic]` on it
  - If the test doesn't start failing, please temporarily remove `#[should_panic]`, and find or create an issue for the new failure
