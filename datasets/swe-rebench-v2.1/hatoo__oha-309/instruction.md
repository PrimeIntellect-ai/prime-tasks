incorrect header host value?
I tried using it like below, hoping to simulate the access to a service on my local machine. The service online is a service of xxx.com, so use the host header to simulate it.

```bash
oha -H "host:xxx.com" -z 30m "http://127.0.0.1:8000"
```

What is received on the server side is

```
Request {
  bodyUsed: false,
  headers: Headers {
  accept: "*/*",
  "accept-encoding": "gzip, compress, deflate, br",
  host: "127.0.0.1:8000, xxx.com",
  "user-agent": "oha/0.6.3"
},
  method: "GET",
  redirect: undefined,
  url: "http://127.0.0.1:8000/"
}
```

It does not meet my expectations. The value of host should be `xxx.com` instead of `127.0.0.1:8000, xxx.com`
