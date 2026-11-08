`web_response.Response.prepared` is `False` after `write_eof()`
`web_response.Response.prepared` is `False` after `write_eof()` (the payload writer goes back to None).

This is a bit mis-leading - any reason not to change `Response.prepared` to `[HIDDEN]`?

### Additional contract requirements

- `Response.prepared` should be True while the response is prepared and remain True after `write_eof()` has been called. It should be False before the response is prepared.
