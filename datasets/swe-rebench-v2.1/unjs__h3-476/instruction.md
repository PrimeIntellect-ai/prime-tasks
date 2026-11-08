`proxyRequest()` doesn't take into account header casing when overriding headers.
If a header is sent by the client with one casing and it's overridden with another in `proxyRequest` they'll both be sent.

https://github.com/unjs/h3/blob/a3192fb919034bb952f6b75271f50e4732ed7d8e/src/utils/proxy.ts#L42-L49
