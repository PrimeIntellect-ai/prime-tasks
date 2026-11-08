OSError: [Errno 9] Bad file descriptor with uvloop
### Describe the bug

Hello! After updating aiohttp to 3.11.13 we see new errors.

### To Reproduce

I don't know how to reproduce these errors, but it seems they are somehow connected with cancellation.

### Expected behavior

No errors

### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/aiohttp/connector.py", line 1123, in _wrap_create_connection
    connection = await self._loop.create_connection(
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "uvloop/loop.pyx", line 2076, in create_connection
  File "uvloop/loop.pyx", line 2066, in uvloop.loop.Loop.create_connection
asyncio.exceptions.CancelledError

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/cian_http/client.py", line 159, in request
    async with self._get_session().request(
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/client.py", line 1425, in __aenter__
    self._resp: _RetType = await self._coro
                           ^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/client.py", line 703, in _request
    conn = await self._connector.connect(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/connector.py", line 548, in connect
    proto = await self._create_connection(req, traces, timeout)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/connector.py", line 1056, in _create_connection
    _, proto = await self._create_direct_connection(req, traces, timeout)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/connector.py", line 1380, in _create_direct_connection
    transp, proto = await self._wrap_create_connection(
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/aiohttp/connector.py", line 1141, in _wrap_create_connection
    sock.close()
  File "/usr/local/lib/python3.12/socket.py", line 505, in close
    self._real_close()
  File "/usr/local/lib/python3.12/socket.py", line 499, in _real_close
    _ss.close(self)
OSError: [Errno 9] Bad file descriptor
```

### Python Version

```console
3.13.1
```

### aiohttp Version

```console
3.11.13
```

### multidict Version

```console
6.1.0
```

### propcache Version

```console
0.3.0
```

### yarl Version

```console
1.18.3
```

### OS

Debian 12.9

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- When the connector fails to close the socket after a failed connection attempt, it raises `aiohttp.ClientConnectionError` instead of letting the `OSError` raised while closing the socket propagate to the caller.
