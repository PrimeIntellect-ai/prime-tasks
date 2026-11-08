unexpected init with empty url when using -H
$ fortio curl -H Host:httpbin  http://35.193.254.22/headers
17:58:00 E http.go:100> unexpected init with empty url

### Additional contract requirements

Using `fortio curl -H` with a target URL must not initialize the request with an empty URL. The request must proceed to the supplied URL and include the supplied header.
