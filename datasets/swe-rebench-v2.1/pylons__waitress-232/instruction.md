[] notation for IPv6 with X-Forwarded-For
After upgrading to Waitress 1.2.0 and letting it handle `X-Forwarded-For` headers, the WSGI environment `REMOTE_ADDR` is populated with IPv6 using the `[]` notation, for instance `'[2a02::1]'`.

While the WSGI specification doesn't say anything about `REMOTE_ADDR`, it is a bit surprising since this notation cannot be used with `ipaddress`:

```python
>>> import ipaddress
>>> ipaddress.ip_address('2a02::1')
IPv6Address('2a02::1')
>>> ipaddress.ip_address('[2a02::1]')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/lib/python3.4/ipaddress.py", line 54, in ip_address
    address)
ValueError: '[2a02::1]' does not appear to be an IPv4 or IPv6 address
```

### Additional contract requirements

- The value placed in `REMOTE_ADDR` must be the bare IPv6 address with the surrounding `[]` brackets removed, so that it can be parsed by `ipaddress.ip_address` (for example `'[2a02::1]'` must become `'2a02::1'`).
- This unbracketed formatting applies to IPv6 addresses obtained from the `Forwarded` header as well as from `X-Forwarded-For`.


- When a `Forwarded` header identifies the client port as `3821`, the WSGI environment must set `REMOTE_PORT` to `'3821'`.
