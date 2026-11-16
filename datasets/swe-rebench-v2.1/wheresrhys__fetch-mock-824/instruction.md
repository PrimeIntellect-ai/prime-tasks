Add support for all the types of body in the fetch spec
[arrayBuffer()](https://developer.mozilla.org/en-US/docs/Web/API/Response/arrayBuffer)
[blob()](https://developer.mozilla.org/en-US/docs/Web/API/Response/blob)
[bytes()](https://developer.mozilla.org/en-US/docs/Web/API/Response/bytes)
[clone()](https://developer.mozilla.org/en-US/docs/Web/API/Response/clone)
[formData()](https://developer.mozilla.org/en-US/docs/Web/API/Response/formData)
[json()](https://developer.mozilla.org/en-US/docs/Web/API/Response/json)
[text()](https://developer.mozilla.org/en-US/docs/Web/API/Response/text)

### Additional contract requirements

- With the default configuration, a response body that is a Blob containing `"test value"` must have a `content-length` header of `10`; an ArrayBuffer, TypedArray, or DataView containing the tested UTF-16 `"test value"` data must have a `content-length` header of `20`; and a URLSearchParams body containing `field=value` must have a `content-length` header of `11`. Do not set a `content-length` header for ReadableStream or FormData response bodies.
