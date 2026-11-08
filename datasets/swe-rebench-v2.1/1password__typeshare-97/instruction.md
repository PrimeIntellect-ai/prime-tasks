null content is no longer optional
https://github.com/1Password/typeshare/pull/82/

This PR changed `undefined` to `null` however it removed the optional operator (from `content?: undefined` to `content: null`)

This seems like a change that should at the very least be a setting.

This is useful if a rust FFI interface allows optional parameters to be passed.

Before one could express an interface that did not require `content: null` to be passed (as this is useless) and now it is required.

I propose `content?: null` be allowed. While this does mean that the type is effectively `content?: null | undefined` this allows for a better quality of life when allowing to not send an empty content over FFI

### Additional contract requirements

The accepted resolution restores the TypeScript output that existed before PR #82.
The generated TypeScript must use `undefined` (not `null`) for Rust unit data, and
a variant that has no data must have an optional `content` property:

- A Rust unit type `()` is rendered as the TypeScript type `undefined`.
- An enum variant with no data (for example `Red`) is rendered as
  `{ type: "<VariantName>", content?: undefined }`, so callers may omit the
  `content` property entirely.
- An enum variant whose single data item is the unit type (for example `HasAUnit(())`)
  is rendered as `{ type: "<VariantName>", content: undefined }`.
