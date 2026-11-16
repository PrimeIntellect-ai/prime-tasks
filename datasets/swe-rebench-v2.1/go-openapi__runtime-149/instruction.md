Transfer-Encoding: chunked does not imply a body is present
Consider a service written with `go-openapi` receiving an HTTP request with the following attributes:
- GET method
- No content-type header
- No content-length header
- A `transfer-encoding: chunked` header
- A single, empty chunk (ie: the body transmitted is semantically empty, but does consume bytes on the HTTP body as is consistent with chunked encoding)

I see in practice that the code assumes the default `content-type: application/octet-stream` for this request because it believes there is a body. By assuming the default content type, service specs that do not explicitly support octet-stream will reject this request as invalid (HTTP 415). I believe the code responsible for deciding whether a request gets a content-type based on the presence of a request body is here: https://github.com/go-openapi/runtime/blob/master/request.go#L45

I've been struggling to definitively prove or disprove whether this behavior is strictly correct according to https://tools.ietf.org/html/rfc2616#section-14.17 and https://tools.ietf.org/html/rfc2616#section-14.41

Specifically, I interpret the RFC as saying:
- Transfer encoding and content length are mutually exclusivel. You can choose to use one or the other without changing the semantics of the message.
- Transfer encoding is a property of the message, not the entity.
- Content-Type is a property of the entity.

Reviewing https://github.com/go-openapi/runtime/blob/master/request.go#L45 it feels like..

// HasBody returns true if this method needs a content-type
func HasBody(r *http.Request) bool {
	return len(r.TransferEncoding) > 0 || r.ContentLength > 0
}

..is suggesting that any request with a non-zero content length has a body. I believe this is correct. However, it also suggests that any request with a transfer-encoding header has a body and, according to the comment, "needs a content-type". Since the entity can still be empty (ie: a single empty chunk), and empty entities do not require a content-type, this seems wrong.

I'd like to start a discussion on whether this is a bug, or if there is additional nuance in the RFC or other practicalities that make the current behavior desirable.

### Additional contract requirements

- `HasBody(r *http.Request) bool` in package `runtime` reports whether a request needs a content type. A request with a non-zero content length, or whose entity contains bytes, has a body. A request with `Transfer-Encoding: chunked` but an empty entity does not have a body and must not require a content type.
