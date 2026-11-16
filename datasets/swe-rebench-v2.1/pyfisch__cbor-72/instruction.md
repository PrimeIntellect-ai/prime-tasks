Detecting invalid cbor when deserializing multiple objects
I am deserializing multiple objects from a slice (like in https://github.com/pyfisch/cbor/issues/20).

I am using the EOF error to detect when I reached the last object, but I have no way to distinguish between an actual EOF and an invalid cbor object.

It would be great to have an `Iter` implementation that does the right thing or that the thrown error had not the current offset in the stream but the offset where the deserialization began.

### Additional contract requirements

- `Deserializer::into_iter<T>(self)` provides an iterator over consecutive CBOR values of type `T`. Each valid value is yielded as `Some(Ok(value))`; clean exhaustion is signalled by `None`; and decoding failures are yielded as `Some(Err(error))`.
- The error type exposes the public predicate `Error::is_eof(&self) -> bool`, which returns `true` exactly when the failure was caused by prematurely reaching the end of the input and `false` for malformed CBOR (for example an unassigned type code). The stream iterator must report malformed CBOR with an error for which `is_eof()` is `false`, so callers can distinguish an actual EOF from an invalid CBOR object.
