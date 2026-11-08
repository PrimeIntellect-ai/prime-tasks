EmptyStreamReader(StreamReader) inheritance broken
### Describe the bug

`EmptyStreamReader` does **no** longer provide the attribute `total_bytes`.

(It looks like the introduction of `__slots__` in `StreamReader` might be the reason - in combination with `EmptyStreamReader.__init__` not calling `StreamReader.__init__`.)

### To Reproduce

Get an instance of an aiohttp `EmptyStreamReader`. Lets call it `reqStream`.

Get `reqStream.total_bytes`.

An `AttributeError `is raised.


### Expected behavior

Access to `reqStream.total_bytes` succeeds - like in 3.10.11.


### Logs/tracebacks

```python-traceback
if reqStream.total_bytes:
   ^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'EmptyStreamReader' object has no attribute 'total_bytes'

(TB snippet from our code - with reqStream being an aiohttp EmptyStreamReader in that moment.)
```

### Python Version

```console
3.11.9
```

### aiohttp Version

```console
3.11.11
```

### multidict Version

```console
6.1.0
```

### propcache Version

```console
0.2.1
```

### yarl Version

```console
1.18.3
```

### OS

Windows

### Related component

Server, Client

### Additional context

_No response_

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct
