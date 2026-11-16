Response header validation case sensitivity
**Describe the bug**
Accrording to #119 header names should be compared in case insensitive fashion.

When ETag response header is defined with [`ETag`](https://www.rfc-editor.org/rfc/rfc7232#section-2.3) canonical name
```
ETag string `header:"ETag" json:"-" required:"true"`
```
response validation error is thrown (missing etag header value) even if `ETag` field is populated in response struct. No such error when response struct is defined with `Etag` header name

```
ETag string `header:"Etag" json:"-" required:"true"`
```
**Expected behavior**
No response validation error thrown when `header:"ETag"` is used in struct definition.

### Additional contract requirements

- Response validation must compare header names case-insensitively, so a response struct field tagged with a canonical HTTP header name (for example `header:"ETag"`) is validated against the value supplied under the canonical header name (for example `Etag`).
- When such a field is populated, response validation must succeed: the response is written with HTTP status 200 and the header is set to the field value.
