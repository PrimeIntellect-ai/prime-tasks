Health check invalid port number
Health check are always created in consul with port number from $PORT0 marathon variable. This is only valid for health checks with `Port Type: Port Index`.
For health checks with `Port Type: Port Number` port number should be taken from key "port" from marathon health check definition.

Eg.: marathon health check definition with `Port Type: Port Number` with static port `8123`:

```
"healthChecks": [
    {
      "path": "/v1/version",
      "protocol": "HTTP",
      "gracePeriodSeconds": 60,
      "intervalSeconds": 10,
      "timeoutSeconds": 5,
      "maxConsecutiveFailures": 3,
      "ignoreHttp1xx": false,
      "port": 8123
    }
  ]
```

So there is `"port": 8123` instead of `"portIndex": 0,`.

This check in consul looks like:
```
  {
    "ModifyIndex": 5488518,
    "CreateIndex": 5488430,
    "Node": "dev-mesos-p2",
    "CheckID": "service:ops_mesos-dns.cd314424-6b12-11e6-8d24-0242f3fd597e",
    "Name": "Service 'mesos-dns' check",
    "Status": "critical",
    "Notes": "",
    "Output": "Get http://10.14.30.74:31313/v1/version: dial tcp 10.14.30.74:31313: getsockopt: connection refused",
    "ServiceID": "ops_mesos-dns.cd314424-6b12-11e6-8d24-0242f3fd597e",
    "ServiceName": "mesos-dns"
  }
```

Port number should be `8123` instead of `31313`.
Port for check was taken from $PORT0 instead of static port key from check definition.
