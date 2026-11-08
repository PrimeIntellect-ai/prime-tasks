Handling a BOM with .json()
Anybody know how I should be handling a BOM with a returned json payload? Right now i'm getting this error when calling res.json()
`Exception: FetchError: invalid json response body at https://api_that_returns_json_with_bom reason: Unexpected token ? in JSON at position 0`

I tried adding an Accept header of `application/json; charset=utf-8` but that didn't resolve the issue.

### Additional contract requirements

- `Response.text()` must decode the body as UTF-8 and strip a leading UTF-8 byte-order mark (BOM, U+FEFF) from the returned string, so that a body whose bytes begin with a BOM decodes to the text without the BOM.


- - `Response.arrayBuffer()` must preserve a leading UTF-8 BOM in the returned raw bytes.
