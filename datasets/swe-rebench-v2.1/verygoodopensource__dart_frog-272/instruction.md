feat: expose HttpConnectionInfo
**Description**

As a developer, I want to have easy access to the [`HttpConnectionInfo`](https://api.dart.dev/stable/2.17.6/dart-io/HttpConnectionInfo-class.html) so that I can access the remote address and/or port.

This can be surfaced via the `RequestContext`:

```dart
Response onRequest(RequestContext context) {
[HIDDEN]
}
```

### Additional contract requirements

- In a handler, incoming connection details are available as `context.request.connectionInfo`.
- For a request served on `localhost`, `context.request.connectionInfo.remoteAddress.address` must be `'::1'`.
