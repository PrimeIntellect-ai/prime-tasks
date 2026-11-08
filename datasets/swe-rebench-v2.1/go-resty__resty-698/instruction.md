How to set Content-Lenght=0 with nil Body?
resty v2.7.0
go 1.20

I use the following code to test:

```go
func main() {
	c := resty.New()

	c.SetPreRequestHook(func(c *resty.Client, r *http.Request) error {
		fmt.Println("zzzzzz", r.Body)
		return nil
	})

	c.R().SetContentLength(true).SetBody(nil).Get("http://10.233.32.117:12233")
}
```

I got following on stdout:

```
zzzzz {}
```

It seems that the rawBody is reassigned to `{}`

And I got following on tcpdump:

```
GET / HTTP/1.1
Host: 10.233.32.117:12233
User-Agent: go-resty/2.7.0 (https://github.com/go-resty/resty)
Accept-Encoding: gzip

.....
```

It seems that although I set the `nil` body and `setContentLength=true`，its not working as expected? anything I missed?

### Additional contract requirements

- For a request configured with `SetContentLength(true)` and `SetBody(nil)`, the HTTP request sent to the server must include `Content-Length: 0` on the wire.
