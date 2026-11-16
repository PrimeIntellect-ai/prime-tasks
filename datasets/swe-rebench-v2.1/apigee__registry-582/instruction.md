Registry API: Improve handling of compressed API specs
Because API specs can occasionally be large enough to exceed gRPC message size limits but also compress extremely well, we encourage users to compress specs before uploading them. But gzip encoding can include timestamps and other variations that make compressions non-unique, so the **SHA hashes that we compute for specs should be based on uncompressed specs** - allowing them to be unique, so that we can use them to detect meaningful changes to specs. **Spec content size should probably also be the uncompressed spec size**.

Currently, for user convenience, the /contents singleton returns uncompressed specs, but this breaks downloads for specs greater than the gRPC maximum message size (4MB). To address this, **the GetSpecContents method should provide some mechanism for user control of the compression of returned values** - having /contents return the uncompressed specs makes it easier to import specs into third-party tools, so this should at least be available as an option, if not the default.

### Additional contract requirements

- For a spec stored with a gzip MIME type, when the incoming request metadata contains `accept-encoding: gzip`, `GetApiSpecContents` must return the stored contents byte-for-byte unchanged.
- - For a spec stored without a gzip MIME type, when the incoming request metadata contains `accept-encoding: gzip`, `GetApiSpecContents` must return the stored contents byte-for-byte unchanged.
- When the incoming request metadata does not contain `accept-encoding: gzip`, `GetApiSpecContents` must return the uncompressed contents (decompressing stored gzip contents when necessary).
- The `hash` and `size_bytes` fields returned for an `ApiSpec` must be computed from the uncompressed spec contents, even when the spec is stored with a gzip MIME type.
