IPv6 address support for `--connect-to`
I wrote the code for this so I'm to blame 🙈  but it just splits across `:` and expects 4 tokens, which obviously doesn't work for IPv6 addresses.

Since curl supports it, and oha's feature is modelled after curl's, I think it should support IPv6 syntax with brackets:

```shell
$ curl -I https://example.org --connect-to 'example.org:443:[2606:2800:220:1:248:1893:25c8:1946]:443'
HTTP/2 200
content-encoding: gzip
accept-ranges: bytes
age: 295951
cache-control: max-age=604800
content-type: text/html; charset=UTF-8
date: Fri, 27 May 2022 09:52:13 GMT
etag: "3147526947+gzip"
expires: Fri, 03 Jun 2022 09:52:13 GMT
last-modified: Thu, 17 Oct 2019 07:18:26 GMT
server: ECS (bsa/EB23)
x-cache: HIT
content-length: 648
```

### Additional contract requirements

The `--connect-to` option accepts a value of the form `host:port:target_host:target_port`, where `target_host` may be an IPv6 address enclosed in `[` and `]`.

If the value does not follow this syntax, if either port cannot be parsed as a `u16`, or if the IPv6 bracket format is malformed, the program exits with a non-zero status.
