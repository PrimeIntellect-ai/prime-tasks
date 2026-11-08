server: Allow to access underlying net.Conn
My use-case is obtaining the full PROXY header from https://github.com/pires/go-proxyproto.

Lazy solution: Just add net.Conn into ConnectionState.
But I feel like [HIDDEN] is
a better idea. We then can just [HIDDEN] (and probably Conn.Hostname()).

### Additional contract requirements

- When creating a backend session, the server must provide the connection as `*smtp.Conn`, and that object must expose the underlying client connection through `Conn.Conn()`.
- Retaining the exported `ConnectionState` type for compatibility is permitted; its removal is not required.
