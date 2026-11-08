ClientDigestMiddleware doesn't work like browsers
### Describe the bug

Once a browser has a challange it sends the authenticate header on subsequent requests preemptively.  We should work the same. This behavior is described in https://datatracker.ietf.org/doc/html/rfc7616#section-3.6

### To Reproduce

Try digest auth on enphase envoy. It only works on the first request because it expected preemptive auth on subsequent requests

### Expected behavior

Behave like browsers by default

### Logs/tracebacks

```python-traceback
n/a
```

### Python Version

```console
$ python --version
n/a
```

### aiohttp Version

```console
$ python -m pip show aiohttp
3.12.7
```

### multidict Version

```console
$ python -m pip show multidict
n/a
```

### propcache Version

```console
$ python -m pip show propcache
n/a
```

### yarl Version

```console
$ python -m pip show yarl
n/a
```

### OS

linux

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

After a Digest challenge establishes a protection space, reuse the credentials preemptively for later requests within that space by default. Do not send the credentials preemptively to URLs outside that protection space.
