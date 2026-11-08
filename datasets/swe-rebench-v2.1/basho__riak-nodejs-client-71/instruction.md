Support for setting `Content Encoding` on RiakObjects [JIRA: CLIENTS-429]
We use the content encoding field when storing compressed objects in Riak. This is currently supported in RiakPBC client (https://github.com/nlf/riakpbc), which we are moving from.

I have added the field and raised a PR if that helps.

### Additional contract requirements

- Add a public method `setContentEncoding(contentEncoding)` on `RiakObject` (module `lib/commands/kv/riakobject`) that associates the given content encoding string with the object and returns the `RiakObject` so that calls can be chained.
- Add a public method `getContentEncoding()` on `RiakObject` that returns the content encoding previously set on the object, or `undefined` if none was set.
- The content encoding set on a `RiakObject` is persisted when the object is stored, and is available on the `RiakObject` returned when a stored object is read back.
