Add support for open_revs key to Get()
To do replications properly, the Get() method needs the option to return multiple (versions of) documents when the `open_revs` option is true.

To accomplish this, perhaps the `Row` type can be merged into the `Rows` type. If done properly, this should require no changes to existing code, but would allow a simple `Get()` to return an iterator.

To make this work, some changes need to be made to `Rows`:

- [x] The `ScanDoc()` method needs to forward errors. Probably all others should do the same for consistency, and it might be worth considering whether `Query()`, `AllDocs()`, etc, should return errors directly, or delay them until the iterator, as `Get()` does
- [x] The iterator must be made immediately ready. At present, `Next()` must be called before the first use. This complicates looping. The `for rows.Next()` idiom would break. Not sure how to handle this. Maybe the first call to `ScanDoc` (or related) could trigger a `Next()`, in the case of a single-result usage? Done in #559
- [x] `Rows` will need to auto-close resources after all resources are read, or on error, at least in the single-use `Get()` case, otherwise we'll have memory leaks. Done in #559
- [x] Extend the `Rows` type to expose the elements of `Row` that are not already there:
    - [x] <strike>ContentLength</strike> (removed in #564)
    - [x] Rev (#561)
    - [x] Body (skipping)
    - [x] Attachments (#560)
- [x] Switch Get() to use the new multi-result return type (#565)
- [ ] Modify Get() to support returning multiple documents when open_revs is passed

### Additional contract requirements

- The default `Accept` header for `Get()` must be exactly `multipart/mixed, multipart/related, application/json`.
- For a multipart response part representing a missing revision, the corresponding row's error message must be exactly `missing`.
