WebSocket.close() does not close the connection
```
WebSocket.prototype.close = function(code, data) {
  if (this.readyState == WebSocket.CLOSING || this.readyState == WebSocket.CLOSED) return;
  if (this.readyState == WebSocket.CONNECTING) {
    this.readyState = WebSocket.CLOSED;
    return;
  }
```

So, if I create a client WebSocket and, while connecting, I call `close()` on it then it does nothing. Instead the handshake continues.

I see that `http.Agent` is in use and I do not know how it works. Anyhow I expect that a WebSocket client should be able to close/abort the TCP connection at any time once the GET has been sent and before the 101 arrives.
