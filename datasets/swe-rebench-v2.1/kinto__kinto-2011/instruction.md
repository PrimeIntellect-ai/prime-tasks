DELETE /v1/accounts raises a 500
```
$ http DELETE https://natim.alwaysdata.net/v1/accounts --auth admin:admin
HTTP/1.1 500 Internal Server Error
Access-Control-Expose-Headers: Retry-After, Alert, Backoff, Content-Length
Content-Length: 177
Content-Type: application/json
Date: Mon, 28 Jan 2019 20:45:56 GMT
Via: 1.1 alproxy
X-Content-Type-Options: nosniff
```

```
  File "/home/natim/kinto/kinto/kinto/plugins/accounts/views.py", line 221, in on_account_changed
    username = request.matchdict["id"]
KeyError: 'id'
```
