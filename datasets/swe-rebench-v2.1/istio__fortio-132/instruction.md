runtime error: slice bounds out of range panic fhttp.(*BasicClient).readResponse istio.io/fortio/fhttp/http.go:718

https://k8s-gubernator.appspot.com/build/istio-prow/pull/istio_istio/1041/e2e-suite-rbac-auth/810/

```
I0215 03:13:51.270] === RUN   Test503sDuringChanges
I0215 03:13:51.270] 2018-02-15T03:13:51.268953Z	info	I httprunner.go:72> Starting http test for http://35.194.88.83/fortio/debug with 8 threads at 8.0 qps
I0215 03:13:52.329] Starting at 8 qps with 8 thread(s) [gomax 4] for 20s : 20 calls each (total 160)
I0215 03:14:00.269] 2018-02-15T03:14:00.269235Z	info	Changing rules mid run to v1/v2
I0215 03:14:00.270] 2018-02-15T03:14:00.269420Z	info	Running command /home/bootstrap/go/out/linux_amd64/release/istioctl -n simple-auth-test-bb09b462ca5b49788df8 create -f /home/bootstrap/go/src/istio.io/istio/tests/e2e/tests/simple/routingrule1.yaml
I0215 03:14:00.592] 2018-02-15T03:14:00.592542Z	info	Command output:
I0215 03:14:00.593]  Created config route-rule/simple-auth-test-bb09b462ca5b49788df8/rule-1 at revision 3798854
I0215 03:14:00.593] , err: <nil>
W0215 03:14:02.945] panic: runtime error: slice bounds out of range
W0215 03:14:02.945]
W0215 03:14:02.945] goroutine 71 [running]:
W0215 03:14:02.945] istio.io/istio/vendor/istio.io/fortio/fhttp.(*BasicClient).readResponse(0xc42020a2a0, 0xc42000e038)
W0215 03:14:02.945] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/fhttp/http.go:718 +0x210b
W0215 03:14:02.945] istio.io/istio/vendor/istio.io/fortio/fhttp.(*BasicClient).Fetch(0xc42020a2a0, 0xd, 0xc4204d1c50, 0x1, 0x1, 0xc4204d1c38)
W0215 03:14:02.945] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/fhttp/http.go:601 +0x460
W0215 03:14:02.946] istio.io/istio/vendor/istio.io/fortio/fhttp.(*HTTPRunnerResults).Run(0xc420091d90, 0x2)
W0215 03:14:02.946] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/fhttp/httprunner.go:52 +0xd7
W0215 03:14:02.946] istio.io/istio/vendor/istio.io/fortio/periodic.runOne(0x2, 0xc42001a180, 0xc42008cb40, 0xc42008cb90, 0x14, 0xbe995c9c13976f9f, 0x209644baf1, 0xdccb00, 0xc4204c6080)
W0215 03:14:02.946] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/periodic/periodic.go:481 +0x235
W0215 03:14:02.946] istio.io/istio/vendor/istio.io/fortio/periodic.(*periodicRunner).Run.func1(0xc42001a180, 0x14, 0xbe995c9c13976f9f, 0x209644baf1, 0xdccb00, 0xc4204c6080, 0xc420016c90, 0x2, 0xc42008cb40, 0xc42008cb90)
W0215 03:14:02.946] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/periodic/periodic.go:398 +0x8b
W0215 03:14:02.946] created by istio.io/istio/vendor/istio.io/fortio/periodic.(*periodicRunner).Run
W0215 03:14:02.946] 	/home/bootstrap/go/src/istio.io/istio/vendor/istio.io/fortio/periodic/periodic.go:397 +0x4e3
W0215 03:14:02.964] make: *** [e2e_simple] Error 1
```

### Additional contract requirements

- A chunked HTTP response may send and flush its headers before sending the first chunk-size line. The response reader must handle this delay without panicking and allow the request to complete with the response status and data.
