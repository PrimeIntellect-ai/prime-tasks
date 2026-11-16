Consider adding top-level attributes
**Syntax:** `#![attribute_name]` (like in Rust)

After reading https://ozkriff.github.io/2017-12-01--devlog.html where @ozkriff said that his configs (https://raw.githubusercontent.com/ozkriff/zemeroth_assets/master/objects.ron) aren't looking very nice because of how RON handles newtypes, I thought about adding attributes which allow to configure RON for your needs. Not only would this allow for toggles like `#![unwrap_newtypes]`, but it could also be used to deal with new features. That way, we can just enforce that you need `#![feature_name]` to enable a RON feature, such that a parser without support for that feature can return a simple and understandable error.

### Additional contract requirements

- The concrete top-level attribute syntax is `#![enable(attribute_name)]`, where `attribute_name` is a supported extension identifier.
- One or more attributes may appear before the value, e.g. `#![enable(unwrap_newtypes)] #![enable(unwrap_newtypes)]`.
- Whitespace and comments are allowed between the tokens of an attribute.
- The extension `unwrap_newtypes` toggles RON's newtype handling: when enabled, a newtype struct is deserialized from its inner value without the wrapper.
- Attribute parsing failures are reported through the `Result` returned by `from_str` using these public `ParseError` variants:
  - `ParseError::ExpectedAttribute` when a `#` is not followed by a well-formed attribute.
  - `ParseError::ExpectedAttributeEnd` when an attribute is missing its closing `)` and `]`.
  - `ParseError::NoSuchExtension(String)` when the attribute names an unsupported extension.
