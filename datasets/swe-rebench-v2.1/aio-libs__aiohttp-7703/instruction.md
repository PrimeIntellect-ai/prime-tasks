HTTP method and version REs are prefix matched
### Describe the bug

The HTTP parser only validates that methods and versions have a valid prefix, instead of validating the entire method and version. For example, the following is incorrectly accepted by the parser:
```
GET\xff / HTTP/1.1\xff\r\n
\r\n
```

### To Reproduce

1. Start an AIOHTTP server.
2. Send it the request above.
3. Observe that it responds normally.

### Expected behavior

The request should be rejected.

### Logs/tracebacks

```python-traceback
N/A
```


### Python Version

```console
$ python --version
Python 3.11.6
```


### aiohttp Version

```console
$ python -m pip show aiohttp
Name: aiohttp
Version: 4.0.0a2.dev0
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /app/aiohttp/env/lib/python3.11/site-packages
Requires: aiosignal, frozenlist, multidict, yarl
Required-by:
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
Location: /app/aiohttp/env/lib/python3.11/site-packages
Requires:
Required-by: aiohttp, yarl
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
Location: /app/aiohttp/env/lib/python3.11/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

Alpine Linux 3.18.0

### Related component

Client

### Additional context

[HIDDEN]

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
