TLS follow-up: determine why http2Round only transport still supports http1
The http2RoundTripper will speak protocols other than http 2 (e.g. http1).

It shouldn't.

Please fix this. If it turns out that this outcome cannot be realized because we are misunderstanding what support client-go provides on this subject, then let's discuss how we should change the code to better work with that library.

Follow-up from #820

https://github.com/vmware-tanzu/pinniped/blob/cd686ffdf31ae2a5f7241cd8d3ddf304c0684a19/internal/concierge/impersonator/impersonator.go#L474
