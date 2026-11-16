Support for const_into_str to Enable Static String Conversion in Const Context
Currently, the `strum` library does not support converting enum variants into static strings within a const context. This limitation arises because the library uses the `From` trait, which cannot have const methods, even in nightly Rust. This issue becomes particularly significant when attempting to use [concatcp](https://docs.rs/const_format/latest/const_format/macro.concatcp.html) to concatenate two static strings in a const context.

To address this limitation, I propose the addition of a new enum meta attribute, `const_into_str`. This attribute would enable generating an additional public const function for enums, allowing conversion to static strings in a const context.

This enhancement would greatly improve `strum`'s functionality by allowing more flexible and performant use of enums in constant expressions. I have prepared an implementation and will submit a pull request for review.

### Additional contract requirements

Enabling `const_into_str` must preserve the enum's existing conversion to `&'static str` for ordinary, non-const use, including the enum's serialization rules.

When `const_into_str` is enabled, the enum must expose a public `const fn into_str(&self) -> &'static str`. Its result must be usable in a const expression and must follow the enum's configured serialization rules.
