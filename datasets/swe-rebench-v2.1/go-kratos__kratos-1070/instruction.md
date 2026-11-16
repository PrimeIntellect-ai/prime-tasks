DefaultResponseEncoder设置content-type无效
https://github.com/go-kratos/kratos/blob/51a3a3250259eceedb1968ea0ff024dcb8582029/transport/http/context.go#L93

rt，[HIDDEN]（文档里有描述https://golang.org/pkg/net/http/#ResponseWriter），所有的repsponse content-type都是text/plain。

### Additional contract requirements

- When a response is encoded by `DefaultResponseEncoder` after `WriteHeader` has been called, the response must retain the `Content-Type` selected by the encoder rather than falling back to `text/plain`.
