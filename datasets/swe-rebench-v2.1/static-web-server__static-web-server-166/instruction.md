Server crashes with compression-static enabled and root as "."
**Describe the bug**
The server crashes when it receives a request for "/" with static compression enabled and root as ".".
This only happens if the client supports compression

**To Reproduce**
run `static-web-server --root . --compression-static true` and access http://localhost from a client that supports compression

**Expected behavior**
Server should not crash

**Logs/Screenshots**
```
2022-12-02T02:38:26.080893Z  INFO static_web_server::handler: incoming request: method=GET uri=/
2022-12-02T02:38:26.080900Z TRACE static_web_server::static_files: dir: base=".", route=""
2022-12-02T02:38:26.080912Z TRACE static_web_server::compression_static: preparing pre-compressed file path variant of .
thread 'static-web-server' panicked at 'called `Option::unwrap()` on a `None` value', src/compression_static.rs:34:53
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
[1]    368327 IOT instruction  static-web-server -p 8080 --root . --compression-static true -g trace
```

**Environment and Specs**
 - static-web-server: 2.14.0
 - OS: Debian bookworm/sid Linux 6.0.0
 - Client: Firefox 107.0

**Additional context**
Add any other context about the problem here if needed.
