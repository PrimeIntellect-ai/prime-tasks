Add support for echo server https when cert/key are provided (like for grpc server)
`-cert` option says:
```
  -cert Path
    	Path to the certificate file to be used for client or server TLS
```

So tried to use `fortio server -cert ca-cert.pem  -key ca-key.pem`:
```
$ ./fortio-linux_amd64-1.39.1/usr/bin/fortio server -cert ca-cert.pem  -key ca-key.pem  -loglevel debug
02:17:47 I logger.go:148> Log level is now 0 Debug (was 2 Info)
02:17:47 V stats.go:528> Will use [50 75 90 99 99.9] for percentiles
02:17:47 Fortio 1.39.1 tcp-echo server listening on tcp [::]:8078
02:17:47 Fortio 1.39.1 udp-echo server listening on udp [::]:8078
02:17:47 Fortio 1.39.1 grpc 'ping' server listening on tcp [::]:8079
02:17:47 I pingsrv.go:82> Using server certificate ca-cert.pem to construct TLS credentials
02:17:47 I pingsrv.go:83> Using server key ca-key.pem to construct TLS credentials
02:17:47 Fortio 1.39.1 https redirector server listening on tcp [::]:8081
02:17:47 Fortio 1.39.1 http-echo server listening on tcp [::]:8080
02:17:47 Data directory is /build/fortio
02:17:47 REST API on /fortio/rest/run, /fortio/rest/status, /fortio/rest/stop
	 UI started - visit:
		http://localhost:8080/fortio/
	 (or any host/ip reachable on this server)
02:17:47 I fortio_main.go:297> Note: not using dynamic flag watching (use -config to set watch directory)
02:17:47 I fortio_main.go:305> All fortio 1.39.1 h1:XY8vKeajJP7xLz/FhkVv97uwFps8jcQ39HPVfWVkFuE= go1.19.5 amd64 linux servers started!
02:17:56 Echo: GET /echo HTTP/1.1 127.0.0.1:43646 ()  "curl/7.68.0"
02:17:56 Header Host: 127.0.0.1:8080
02:17:56 Header User-Agent: curl/7.68.0
02:17:56 Header Accept: */*
02:17:56 D http_server.go:84> Read 0
02:17:56 D http_utils.go:381> Parsing delay  -> []
02:17:56 D http_server.go:128> Request # 1
```

But it's still HTTP:
```
$ curl  -vv http://127.0.0.1:8080/echo
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> GET /echo HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.68.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Date: Sat, 21 Jan 2023 02:17:56 GMT
< Content-Length: 0
<
* Connection #0 to host 127.0.0.1 left intact
```

HTTPS doesn't work:
```
$ curl  -vv https://127.0.0.1:8080/echo
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*   CAfile: /etc/ssl/certs/ca-certificates.crt
  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* error:1408F10B:SSL routines:ssl3_get_record:wrong version number
* Closing connection 0
curl: (35) error:1408F10B:SSL routines:ssl3_get_record:wrong version number
```

### Additional contract requirements

- Add a public function `ServeTLS(port string, debugPath string, certPath string, keyPath string) (*http.ServeMux, net.Addr)` in package `fortio.org/fortio/fhttp`. It starts the echo/debug HTTP server on `port` (a port number, or `0` to request an OS-assigned free port). When both `certPath` and `keyPath` are non-empty the server serves TLS; otherwise it serves plain HTTP. It returns the mux to which handlers can be attached and the listening address, or nil on failure.
- The `fortio server` command serves the echo/debug endpoint over HTTPS when both `-cert` and `-key` are provided.
