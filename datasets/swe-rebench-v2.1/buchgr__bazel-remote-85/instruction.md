Internal Server Error when object not found in `http_proxy`
With `bazel-remote` running on localhost and an `http_proxy` configured to a remote `bazel-remote`, when an object is looked up remotely and not found, the local `bazel-remote` responds with a 500 Internal Server error.

This is the output from Bazel (0.22.0):
```
 $ bazel test //...
INFO: Using Bazel Remote listening on port 55381
INFO: Running Bazel version 0.22.0.4
INFO: Invocation ID: 243c2863-f4f3-4a27-b35c-8ee3362b4990
INFO: Analysed 40 targets (0 packages loaded, 0 targets configured).
INFO: Found 38 targets and 2 test targets...
WARNING: Error reading from the remote cache:
500 Internal Server Error
Not found

INFO: Elapsed time: 0.886s, Critical Path: 0.63s
INFO: 1 process: 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
```

There are no obvious errors in the local `bazel-remote` log, but I used `tcpdump` to see the packets:

This is Bazel:
```
GET /ac/5a776703f6b95900eba8e7a1779df127f0c61a60610e9e1322c94d3bbe3bd1fd HTTP/1.1
host: 127.0.0.1:55381
connection: keep-alive
accept: */*
```

This is the local `bazel-remote` log:
```
2019/03/01 19:27:46  GET 404                 http://bazel-remote.example.com:8415/ac/5a776703f6b95900eba8e7a1779df127f0c61a60610e9e1322c94d3bbe3bd1fd
2019/03/01 19:27:46 GET /ac/5a776703f6b95900eba8e7a1779df127f0c61a60610e9e1322c94d3bbe3bd1fd: Not found
```

This is the response from the local `bazel-remote`:

```
HTTP/1.1 500 Internal Server Error
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Date: Fri, 01 Mar 2019 19:27:46 GMT
Content-Length: 11

Not found
```

The local `bazel-remote` should reply with an HTTP code 404 Not Found instead of a 500 Internal Server Error.
