HTTP Client: Redirect with 307 (Temporary Redirect) should keep original request method and body
As it stated at [MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/307)
_The method and the body of the original request are reused to perform the redirected request._

But [here](https://github.com/reactphp/http/blob/bc537273d11ee769c723a830e63aa33c0c35a530/src/Io/Transaction.php#L265) request is converted from POST to GET.

### Additional contract requirements

- A `308 Permanent Redirect` response must also reuse the original request method and body for the redirected request, exactly like a `307 Temporary Redirect`.
- When a `307` or `308` redirect is attempted for a request whose body is a streaming `ReadableBodyStream`, the request must be rejected with a `RuntimeException` whose message is exactly `Unable to redirect request with streaming body`.
- For any other redirect status code, the redirected request must use the `GET` method (or keep `HEAD` if the original request used `HEAD`), must not contain `Content-Type` or `Content-Length` headers, and must use an empty body.
- For a `POST` request to `http://example.com` redirected by a `307` response to `http://example.com/new`, with `Content-Type: text/html; charset=utf-8` and `Content-Length: 111`, the redirected request's `getHeaders()` must equal `array('Content-Type' => array('text/html; charset=utf-8'), 'Content-Length' => array('111'), 'Host' => array('example.com'))`.
