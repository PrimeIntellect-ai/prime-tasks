Content-length validation does not handle spaces
Additional validation of Content-Length parsing was introduced in bf90f3a9ad150c45d9d17f189c3368e9a3b8e80f however, the value is not `strip`ed and therefore a value of `'0 '` causes a `ValueError`.

This is a particular issue because if `Content-Length` is the last header in a request and `parse_line` is being called then the `\r\n` of the end of the header is interpreted as a multi-line continuation and appends the space to the end in `HTTPHeaders.parse_line`: [HIDDEN].

@bdarnell

### Additional contract requirements

- Feeding the header lines of a response, one at a time and including the final blank line, into `HTTPHeaders.parse_line` (as an `AsyncHTTPClient` `header_callback` does) must not add trailing whitespace to the last header value.
- A response whose last header is `Content-Length: 0` must be accepted as a zero-length body, whether or not the value is followed by trailing whitespace before the line break.
