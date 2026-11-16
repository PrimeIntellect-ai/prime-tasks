Missing API: `Sink.write(CharSequence)`
At the moment, when receiving data from a mutable `CharSequence`, one has to use `sink.writeString(chars.toString())`, which may be inefficient (copying data to create a `String`, just to then encode it again as UTF-8 bytes in the buffer).

It would be nice to have a `Sink.write(CharSequence)` (or `Sink.writeUtf8(CharSequence)`) extension so we can efficiently transfer characters from a `CharSequence` into a `Buffer` via UTF-8 encoding.

### Additional contract requirements

- The new overload is `Sink.writeString(chars: CharSequence)`, an extension next to the existing `Sink.writeString(string: String)`. It writes every character of `chars` to the sink encoded as UTF-8, so the bytes written for a `StringBuilder` (or any other `CharSequence`) equal the bytes written for an equal `String`.
- Encoding must be correct for all characters, including multi-byte characters and content that spans several internal buffer segments (for example, a long sequence written after a partially filled segment).
- The characters are read from the `CharSequence` directly; the sink must not require converting the `CharSequence` to a `String` first, so its `toString()` must not be called.
- Writing to a closed sink throws `IllegalStateException`, the same as the `String` overload.
