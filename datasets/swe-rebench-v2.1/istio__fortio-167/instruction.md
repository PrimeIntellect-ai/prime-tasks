2*c connection leaks when using the UI to trigger run (regression?)
reloading many times while testing histogram boundary:


http://localhost:8080/fortio/?labels=Fortio&url=http%3A%2F%2Flocalhost%3A8080%2Fecho%3Fdelay%3D1ms%3A90%2C9ms%3A10&qps=100&t=&t=on&n=100&c=10&p=50%2C+75%2C+90%2C+99%2C+99.9&r=0.0000001&H=User-Agent%3A+istio%2Ffortio-0.7.2-pre&H=&H=&runner=http&save=on&load=Start


Starting at 100 qps with 10 thread(s) [gomax 4] : exactly 100, 10 calls each (total 100 + 0)
URL: localhost:8080/echo?delay=1ms:90,9ms:10
```
23:32:05 I uihandler.go:439> UI: GET /fortio/?labels=Fortio&url=http%3A%2F%2Flocalhost%3A8080%2Fecho%3Fdelay%3D1ms%3A90%2C9ms%3A10&qps=100&t=&t=on&n=100&c=10&p=50%2C+75%2C+90%2C+99%2C+99.9&r=0.0000001&H=User-Agent%3A+istio%2Ffortio-0.7.2-pre&H=&H=&runner=http&save=on&load=Start HTTP/1.1 [::1]:61957 ()
23:32:05 I uihandler.go:153> Starting http load request from [::1]:61957 for http://localhost:8080/echo?delay=1ms:90,9ms:10
23:32:05 I uihandler.go:209> New run id 13
23:32:05 I uihandler.go:227> Estimating fixed #call 100 duration to 1 seconds 100
23:32:05 I httprunner.go:72> Starting http test for http://localhost:8080/echo?delay=1ms:90,9ms:10 with 10 threads at 100.0 qps
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 http: Accept error: accept tcp [::]:8080: accept: too many open files; retrying in 5ms
23:32:05 E http.go:663> Read error &{{0xc420e35b00}} {::1 8080 } 0 : read tcp [::1]:62091->[::1]:8080: read: connection reset by peer
23:32:05 http: Accept error: accept tcp [::]:8080: accept: too many open files; retrying in 5ms
23:32:05 E http.go:663> Read error &{{0xc420e35b80}} {::1 8080 } 0 : read tcp [::1]:62092->[::1]:8080: read: connection reset by peer
23:32:05 http: Accept error: accept tcp [::]:8080: accept: too many open files; retrying in 5ms
23:32:05 E http.go:663> Read error &{{0xc4206a1980}} {::1 8080 } 0 : read tcp [::1]:62094->[::1]:8080: read: connection reset by peer
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
23:32:05 E http.go:556> Unable to connect to {::1 8080 } : dial tcp [::1]:8080: socket: too many open files
```

### Additional contract requirements

- Repeated runs of the HTTP load test must not leak connections or goroutines. This must hold both for the default fast HTTP client and for the standard (net/http) client. Keeping a bounded set of idle connections for reuse is not a leak; the number of open connections and goroutines must not keep growing with each run.
- The same must hold when runs are triggered through the web UI.
