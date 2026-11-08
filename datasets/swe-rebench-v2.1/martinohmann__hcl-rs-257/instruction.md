incorrect handling of escaped template interpolations and directives
The following does not fail to parse, but fails the assertion because `$${escaped2}` is split into a `$` literal and the interpolation `${escaped2}`:

```rust
let input = "$${escaped1} ${unescaped} $${escaped2} $$ESCAPED_SHELL_VAR\n$SHELL_VAR";
let parsed: Template = input.parse().unwrap();
let expected = Template::from_iter([
    Element::from("${escaped1} "),
    Element::from(Interpolation::new(Ident::new("unescaped"))),
    Element::from(" ${escaped2} $$ESCAPED_SHELL_VAR\n$SHELL_VAR"),
]);

assert_eq!(parsed, expected);
```

This is a parser bug.

### Additional contract requirements

- Escaped template directives must be treated as literal text: `%%{` yields a literal `%{`, and the directive-looking content that follows must not be interpreted as an active directive.
