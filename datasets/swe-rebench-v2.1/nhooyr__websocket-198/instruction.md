How to set Cross domain origin?
in AcceptOptions struct, I found the `InsecureSkipVerify` field and set it equal to true.  but all clients can connect to the WebSocket server, it includes illegal clients.  in [gorilla](https://github.com/gorilla/websocket) have [CheckOrigin](https://github.com/gorilla/websocket/blob/master/server.go#L66). but there is no the same method. (AcceptOrigins and add AcceptInsecureOrigin is removed in the current version).
```

	// InsecureSkipVerify disables Accept's origin verification behaviour. By default,
	// the connection will only be accepted if the request origin is equal to the request
	// host.
	//
	// This is only required if you want javascript served from a different domain
	// to access your WebSocket server.
	//
	// See https://stackoverflow.com/a/37837709/4283659
	//
	// Please ensure you understand the ramifications of enabling this.
	// If used incorrectly your WebSocket server will be open to CSRF attacks.
	InsecureSkipVerify bool

```

@nhooyr  How to set origin like gorilla's` CheckOrigin`?   Looking forward to your reply, appreciate it.  Thanks.

### Additional contract requirements

- The public `websocket.AcceptOptions` struct must include a field `OriginPatterns []string`.
- `OriginPatterns` lists the host patterns for authorized origins. Each pattern is matched case-insensitively against the host of the request's `Origin` header using `filepath.Match` syntax. The request host is always authorized, and an empty `Origin` header is always authorized.
- `Accept` must apply the configured `OriginPatterns` when verifying the request origin, so that a cross-origin request whose origin host matches one of the patterns is accepted.
