[attributed_text] - Return substrings given a SpanRange
We often work with `SpanRange`s when dealing with `AttributedText`. Currently, to get a substring, we have to access the inner plain text string, and then unpack the `SpanRange` into a start and end value.

Consider offering a plain text substring method on `AttributedText` that takes a `SpanRange` directly.

Also, consider offering a top-level `length` method on `AttributedText`.

### Additional contract requirements

- Provide `AttributedText.substringInRange(SpanRange range)` to return the plain-text substring covered by the range (start inclusive, end exclusive).
- Expose the underlying plain-text content length directly as `AttributedText.length`.
