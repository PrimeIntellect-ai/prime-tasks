`web_response.Response.prepared` is `False` after `write_eof()`
`web_response.Response.prepared` is `False` after `write_eof()` (the payload writer goes back to None).

This is a bit mis-leading - any reason not to change `Response.prepared` to `[HIDDEN]`?

### Additional contract requirements

- `Response.prepared` is false before preparation and true after preparation, including after `write_eof()` completes.
