Host() with  a port fails to match when the host is supplied in the HTTP Host: header
Old issue: http://code.google.com/p/gorilla/issues/detail?id=51

According to section 14.23 of RFC 2616 the Host header can include the port number if the default value of 80 is not used.

See https://github.com/gorilla/mux/blob/master/mux_test.go#L119 for a commented-out test case that fails.

Potential fix is editing [HIDDEN]

The main reason I was using Host() match with a port in the first place is for trying to build reverse routes that include the absolute path as opposed to a relative one.

### Additional contract requirements

- A `Host()` route specifying an explicit port must match a request whose HTTP `Host` header contains the corresponding host and port, and must not match that host with a different port.
- This behavior also applies when the port-bearing host pattern contains variables; matching variable values must be available as route variables.
