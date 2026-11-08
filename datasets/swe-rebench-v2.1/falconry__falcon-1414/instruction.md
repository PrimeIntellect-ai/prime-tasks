fix: Special-case Response.append_header to handle Set-Cookie
When setting cookies directly (e.g., when proxying an upstream response with cookie headers), we must special-case Set-Cookie since the usual method of joining multiple header values with a comma is incorrect in that case.

I've got a prototype fix for this already, so I'll go ahead and work on a PR.

### Additional contract requirements

- `falcon.Response.append_header(name, value)` appends a header to the response. When `name` is `"Set-Cookie"` (case-insensitive), the value is recorded as a raw cookie line so that each cookie is emitted as a separate header line instead of being combined with commas.
- `falcon.Response.set_header(name, value)` raises `ValueError` (or its subclass `falcon.errors.HeaderNotSupported`) when `name` is `"Set-Cookie"` (case-insensitive).
- `falcon.Response.set_headers(headers)` accepts either a mapping or a list of `(name, value)` pairs and raises `ValueError` (or `falcon.errors.HeaderNotSupported`) if any supplied header name is `"Set-Cookie"` (case-insensitive).
- `falcon.Response.get_header(name, default=None)` raises `ValueError` (or `falcon.errors.HeaderNotSupported`) when `name` is `"Set-Cookie"` (case-insensitive).
- `falcon.Response.delete_header(name)` raises `ValueError` (or `falcon.errors.HeaderNotSupported`) when `name` is `"Set-Cookie"` (case-insensitive).
- `falcon.errors.HeaderNotSupported` is a subclass of `ValueError`.
