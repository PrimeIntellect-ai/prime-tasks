Support [Ipv6] format `requested_host` in `--connect-to`
Because `curl` supports it.

```sh
❯ curl -I --connect-to [::0]:80:www.google.com:80 [::0]
HTTP/1.1 404 Not Found
Transfer-Encoding: chunked
Date: Wed, 12 Oct 2022 07:37:31 GMT
Content-Type: text/html; charset=UTF-8
```

```sh
❯ oha --connect-to [::0]:80:www.google.com:80 [::0]
error: Invalid value "[::0]:80:www.google.com:80" for '--connect-to <CONNECT_TO>': requested port must be an u16, but got : cannot parse integer from empty string

For more information try --help
```

Just in case if the parse is hard, it may be good to use separate arguments like..
```sh
❯ oha --connect-to [::0]:80 www.google.com:80 --connect-to host2:port2 host3:port3  [::0]
```
