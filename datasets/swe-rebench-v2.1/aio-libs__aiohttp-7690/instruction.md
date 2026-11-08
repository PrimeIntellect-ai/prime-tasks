`ClientWebSocketResponse.close_code` will be `None` when there are concurrent async task receiving data and closing connection
### Describe the bug

If one asyncio task is waiting on receiving data and another asyncio task is closing the connection. The `ClientWebSocketResponse.close_code` will be `None` after connection closed.

It looks like the following is happening:

1. `close()` called and feed `WS_CLOSING_MESSAGE`: https://github.com/aio-libs/aiohttp/blob/fde452da30f326f4fc50cbf6cbe32d6387c48c0f/aiohttp/client_ws.py#L191-L193
2. `receive()` received `WS_CLOSING_MESSAGE` , mark `self._closing` to be True: https://github.com/aio-libs/aiohttp/blob/fde452da30f326f4fc50cbf6cbe32d6387c48c0f/aiohttp/client_ws.py#L285-L286
[HIDDEN]: https://github.com/aio-libs/aiohttp/blob/fde452da30f326f4fc50cbf6cbe32d6387c48c0f/aiohttp/client_ws.py#L210-L212


### To Reproduce

See the steps in https://github.com/wenleix/aiohttp_recv_upon_close

### Expected behavior

Expect to have closed code 1000, i.e.

```
Waiting for message
Closed code: 1000
```

### Logs/tracebacks

```python-traceback
The actual result is :

Waiting for message
Closed code: None
```
```


### Python Version

```console
$ python --version

Python 3.9.13
```
```


### aiohttp Version

```console
$ python -m pip show aiohttp

Name: aiohttp
Version: 3.8.4
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Requires: aiosignal, async-timeout, attrs, charset-normalizer, frozenlist, multidict, yarl
Required-by:
```
```


### multidict Version

```console
$ python -m pip show multidict

Name: multidict
Version: 6.0.4
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Requires:
Required-by: aiohttp, yarl
```
```


### yarl Version

```console
$ python -m pip show yarl

Name: yarl
Version: 1.9.2
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Requires: idna, multidict
Required-by: aiohttp
```
```


### OS

macOS

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
