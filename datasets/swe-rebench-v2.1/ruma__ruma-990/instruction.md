Remove RawExt
`Raw` is now defined in the same crate as `RawExt`, so the latter can now simply be [HIDDEN]

### Additional contract requirements

- Keep the content-deserialization operation available as an inherent method on `Raw<T>`, without requiring `RawExt` to be imported.
- Remove `RawExt` from the public API.
