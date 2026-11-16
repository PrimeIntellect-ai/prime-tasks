Setting Headers (-H) causes panic
Run Fortio in `server` mode:
```
$ docker run --name fortio --rm -p 8080:8080 -p 8082:8082 -p 8079:8079 istio/fortio:0.7.0 server -loglevel verbose -redirect-port 8082
Fortio 0.7.0 grpc ping server listening on port :8079
UI starting - visit:
http://localhost:8080/fortio/   (or any host/ip reachable on this server)
Https redirector running on :8082
19:55:58 I logger.go:97> Log level is now 1 Verbose (was 2 Info)
19:55:58 V stats.go:491> Will use [50 75 90 99 99.9] for percentiles
19:55:58 V uihandler.go:92> Using resources directory set at link time: /usr/local/lib/fortio
Fortio 0.7.0 echo server listening on port :8080
```

Use `curl` or `load` with `-H`:
```
$ docker run --name client --rm istio/fortio:0.7.0 load -loglevel verbose -H Foo:Bar -curl http://172.17.0.2:8080/debug
19:56:58 I logger.go:97> Log level is now 1 Verbose (was 2 Info)
19:56:58 V http.go:172> Setting regular extra header Foo: Bar
panic: assignment to entry in nil map

goroutine 1 [running]:
net/textproto.MIMEHeader.Add(0x0, 0x7ffe4edfff3b, 0x3, 0x7ffe4edfff3f, 0x3)
	/usr/local/go/src/net/textproto/header.go:15 +0xf7
net/http.Header.Add(0x0, 0x7ffe4edfff3b, 0x3, 0x7ffe4edfff3f, 0x3)
	/usr/local/go/src/net/http/header.go:24 +0x53
istio.io/fortio/fhttp.(*HTTPOptions).AddAndValidateExtraHeader(0xbd9c20, 0x7ffe4edfff3b, 0x7, 0xc420068301, 0x0)
	/go/src/istio.io/fortio/fhttp/http.go:173 +0x35d
main.(*flagList).Set(0xbf6200, 0x7ffe4edfff3b, 0x7, 0x0, 0x0)
	/go/src/istio.io/fortio/fortio_main.go:49 +0x41
flag.(*FlagSet).parseOne(0xc420064060, 0x1, 0x0, 0x0)
	/usr/local/go/src/flag/flag.go:894 +0x3c2
flag.(*FlagSet).Parse(0xc420064060, 0xc4200f6320, 0x6, 0x6, 0x1, 0xc420142220)
	/usr/local/go/src/flag/flag.go:913 +0x60
flag.Parse()
	/usr/local/go/src/flag/flag.go:941 +0x72
main.main()
	/go/src/istio.io/fortio/fortio_main.go:140 +0x2dc

$ docker run --name client --rm istio/fortio:0.7.0 curl -loglevel verbose -H Foo:Bar -curl http://172.17.0.2:8080/debug
19:56:44 I logger.go:97> Log level is now 1 Verbose (was 2 Info)
19:56:44 V http.go:172> Setting regular extra header Foo: Bar
panic: assignment to entry in nil map

goroutine 1 [running]:
net/textproto.MIMEHeader.Add(0x0, 0x7ffe0e225f3b, 0x3, 0x7ffe0e225f3f, 0x3)
	/usr/local/go/src/net/textproto/header.go:15 +0xf7
net/http.Header.Add(0x0, 0x7ffe0e225f3b, 0x3, 0x7ffe0e225f3f, 0x3)
	/usr/local/go/src/net/http/header.go:24 +0x53
istio.io/fortio/fhttp.(*HTTPOptions).AddAndValidateExtraHeader(0xbd9c20, 0x7ffe0e225f3b, 0x7, 0xc420068701, 0x0)
	/go/src/istio.io/fortio/fhttp/http.go:173 +0x35d
main.(*flagList).Set(0xbf6200, 0x7ffe0e225f3b, 0x7, 0x0, 0x0)
	/go/src/istio.io/fortio/fortio_main.go:49 +0x41
flag.(*FlagSet).parseOne(0xc420064060, 0x1, 0x0, 0x0)
	/usr/local/go/src/flag/flag.go:894 +0x3c2
flag.(*FlagSet).Parse(0xc420064060, 0xc4200f6320, 0x6, 0x6, 0x1, 0xc420142220)
	/usr/local/go/src/flag/flag.go:913 +0x60
flag.Parse()
	/usr/local/go/src/flag/flag.go:941 +0x72
main.main()
	/go/src/istio.io/fortio/fortio_main.go:140 +0x2dc
```
[HIDDEN] I will submit a PR to fix the issue.

### Additional contract requirements

- `fhttp.HTTPOptions.AddAndValidateExtraHeader(hdr string) error` accepts a header string containing a field name and value separated by a colon. It returns an error for a malformed header and otherwise records the header so it is included in outgoing HTTP requests. This must work on an `HTTPOptions` value that has not otherwise been initialized.
- `fhttp.HTTPOptions.GetHeaders() http.Header` returns the default headers together with any extra headers that were added. The default headers include a `User-Agent` header.
- `fhttp.HTTPOptions.ResetHeaders()` clears all headers, including the default `User-Agent` header.
