bug: Decoder.Decode() should return io.UnexpectedEOF instead of io.EOF if CBOR data item is truncated
If CBOR data item is truncated at EOF, then Decoder.Decode() should return `io.UnexpectedEOF` instead of `io.EOF`.

### Additional contract requirements

- If `Decode()` returns `io.ErrUnexpectedEOF` for a truncated CBOR data item at EOF, the next call to `Decode()` on that decoder must also return `io.ErrUnexpectedEOF`.
- If the reader returns a non-EOF error while `Decode()` is reading a truncated CBOR data item, `Decode()` must return that same error.
- - When decoding into an `interface{}` destination, if `Decode()` returns `io.ErrUnexpectedEOF` or a non-EOF reader error while reading a truncated CBOR data item, the destination must remain nil.
