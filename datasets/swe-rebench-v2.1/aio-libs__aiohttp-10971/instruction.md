WebSocket prepare property incorrectly reflects prepared state
### Describe the bug

[HIDDEN]

### To Reproduce

```python
wsock = web.WebSocketResponse()
try:
    # Bug can happen when this job times out during `WebSocketResponse `calling `super().prepare()`
    # and `StreamResponse` is inside `await self._start` and client connection is dropped but OS didn't notice
    async with async_timeout(10):
        await wsock.prepare()
except asyncio.TimeoutError:
    if wsock.prepared:
        # This raises because `close()` checks if `self._writer` is not None,
        # which is set inside `StreamResponse._post_start`
        await wsock.close()
```

### Expected behavior

If `wsock.prepared` returns `True`, it should be safe to close the connection.

### Logs/tracebacks

```python-traceback
File "server/api.py", line 264, in handle
    await wsock.close()
  File "aiohttp/web_ws.py", line 329, in close
    raise RuntimeError("Call .prepare() first")
```
```


### Python Version

```console
$ python --version
3.9
```


### aiohttp Version

```console
$ python -m pip show aiohttp
3.7.4.post0
```


### multidict Version

```console
$ python -m pip show multidict
5.1.0
```


### yarl Version

```console
$ python -m pip show yarl
1.6.3
```


### OS

Debian

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- `WebSocketResponse.prepared` must reflect whether the WebSocket is in a state where it is safe to close.
- If `prepare()` fails with an error (for example a timeout) before the handshake response has been written, `prepared` must be `False`.
