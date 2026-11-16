socket.IPPROTO_IPV6 undefined in Python 2.7.12 for Windows
Hi all,

In the current commit (7e807c9), the line 172 of the file waitress/server.py contains:
```python
self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
```
Thing is, IPPROTO_IPV6 is not defined in socket...

Should it be [HIDDEN], while we gently wait for Python to fix this ?
Or should IPV6 be avoided under Windows with Python 2.7 ?

Thanks for the support,

Best,
Nicolas

### Additional contract requirements

- IPv6 server setup must not fail solely because `socket.IPPROTO_IPV6` is absent on the stated platform.
