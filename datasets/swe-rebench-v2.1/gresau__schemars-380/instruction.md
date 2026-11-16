Controlling referenceability in derived schemas
Currently, if I want to make a particular schema appear inline I must implement the entirety `JsonSchema` myself, even though all I want to do is overriding `fn is_referenceable() -> bool { false }`. It would be great if there was an attribute that would let me control referenceability like there are for other options.

### Additional contract requirements

- Add a `#[schemars(inline)]` attribute that can be applied to a struct or enum that derives `JsonSchema`. When this attribute is present, the type's generated `JsonSchema::always_inline_schema()` returns `true`; when the attribute is absent, `always_inline_schema()` returns `false`.

- For a derived struct or enum marked with `#[schemars(inline)]`, its schema must be included directly when used as a nested schema, rather than represented by a `$ref`.
