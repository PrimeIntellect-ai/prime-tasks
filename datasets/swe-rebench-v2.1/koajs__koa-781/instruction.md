pipeling request will lost!
### [Test code](https://gist.github.com/zensh/02f6e665cd7eead9b2e072ce4194a4bf)

### Test result:
```
=== Http server ===
Request count: 1 , Error listeners: 1
Request count: 2 , Error listeners: 1
HTTP/1.1 200 OK
Date: Wed, 20 Jul 2016 02:56:47 GMT
Connection: keep-alive
Content-Length: 1

1HTTP/1.1 200 OK
Date: Wed, 20 Jul 2016 02:56:47 GMT
Connection: keep-alive
Content-Length: 1

2

=== Toa server ===
Request count: 1 , Error listeners: 1
Request count: 2 , Error listeners: 1
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 1
X-Powered-By: Toa
Date: Wed, 20 Jul 2016 02:56:47 GMT
Connection: keep-alive

1HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 1
X-Powered-By: Toa
Date: Wed, 20 Jul 2016 02:56:47 GMT
Connection: keep-alive

2

=== Koa server ===
Request count: 1 , Error listeners: 2
Request count: 2 , Error listeners: 2
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 1
Date: Wed, 20 Jul 2016 02:56:47 GMT
Connection: keep-alive

1
```

### Reason

When server emit a `request`, `responce` instance may not have `socket` for the time being, [_http_server.js](https://github.com/nodejs/node/blob/master/lib/_http_server.js#L487), `this.writable === false` in [application.js](https://github.com/koajs/koa/blob/master/lib/application.js#L199)
