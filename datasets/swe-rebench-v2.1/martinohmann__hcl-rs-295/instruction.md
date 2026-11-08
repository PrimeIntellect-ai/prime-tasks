hcl-edit: attribute key has no span information
```rust
#[test]
fn parsed_body_attribute_has_span_information() {
    use hcl_edit::Span;

    let body = hcl_edit::parser::parse_body("foo = bar").unwrap();
    let first_attr = body.into_attributes().next().unwrap();
    assert!(first_attr.key.span().is_some());
}
```

Is this assertion correct? (it fails)

_If this is confirmed and still open in about 2 weeks then i'll provide a PR with a fix attempt_
