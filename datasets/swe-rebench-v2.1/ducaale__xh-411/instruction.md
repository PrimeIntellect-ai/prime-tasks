panic with compressed response from server
When calling a service that returns a `zstd` compressed response, xh panics.

For example:

```
xh -v HEAD http://hello.com/file.css
HEAD /file.css HTTP/1.1
Accept: */*
Accept-Encoding: gzip, deflate, br, zstd
Connection: keep-alive
Host: hello.com
User-Agent: xh/0.24.0

HTTP/1.1 200 OK
Cache-Control: max-age=604800
Connection: keep-alive
Content-Disposition: inline; filename=file.css
Content-Encoding: zstd
Content-Length: 998
Content-Type: text/css; charset=utf-8
Date: Mon, 03 Mar 2025 18:50:39 GMT
Last-Modified: Fri, 28 Feb 2025 12:28:50 GMT
Server: gunicorn
Vary: Accept-Encoding

thread 'main' panicked at src/decoder.rs:150:79:
called `Result::unwrap()` on an `Err` value: ReadFrameHeaderError(MagicNumberReadError(Error { kind: UnexpectedEof, message: "failed to fill whole buffer" }))
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

Same request with curl works fine.
