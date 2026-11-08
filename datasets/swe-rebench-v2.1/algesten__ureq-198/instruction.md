Timeout is reset on stream when calling `into_reader()`
When calling `into_reader()` on a request, the timeout set with `set_timeout_read` (NOT the deadline `set_timeout`) on the request is reset to no timeout [HIDDEN], and there is no way to set it again.

This makes `set_timeout_read` basically unused except for reading the headers.

### Additional contract requirements

- A request’s `set_timeout_read` timeout must remain effective while reading the response body after `into_reader()` is obtained. This is the per-read timeout, not the overall `set_timeout` deadline.
