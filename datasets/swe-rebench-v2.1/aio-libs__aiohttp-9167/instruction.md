Unpredictable behavior of the server with the issuance of 500 when the "reason" parameter is incorrect.
### Describe the bug

For a long time I could not understand what was the matter, when my server wrote to the logs that it returned one response with the correct status code, and on the client I received "500 Internal Server Error".

After a long discussion, I found out that the server behaves incorrectly if you specify text with several lines in the respone in the "reason" parameter, i.e. with the character "\n" inside, the server simply returns a 500 response but displays a different one in the logs.

### To Reproduce

1. make response with parameter "reason" with simbol "\n".
2. check your log on server
3. check your log on client
4. see that the client received a 500 Internal Server Error instead of the required response

### Expected behavior

It would be nice to prevent this behavior and make it explicit with a server bug!

### Logs/tracebacks

```python-traceback
No
```


### Python Version

```console
Python 3.9.1
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.8.0
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /usr/local/lib/python3.9/site-packages
Requires: aiosignal, async-timeout, attrs, charset-normalizer, frozenlist, multidict, yarl
Required-by: aiobotocore, aiogram, aiohttp-swagger, core, metacore
```


### multidict Version

```console
Name: multidict
Version: 5.1.0
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /home/goov/.local/lib/python3.9/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
Name: yarl
Version: 1.6.3
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /home/goov/.local/lib/python3.9/site-packages
Requires: idna, multidict
Required-by: aio-pika, aiohttp, aiormq
```


### OS

Linux debian

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- Constructing a server response with a `reason` value that contains a newline character (`"\n"`) must raise `ValueError`. This applies to `aiohttp.web.StreamResponse` and its subclasses, such as `aiohttp.web.Response`.
- Constructing an HTTP exception with a `reason` value that contains a newline character (`"\n"`) must raise `ValueError`. This applies to `aiohttp.web.HTTPException` and its subclasses, such as `aiohttp.web.HTTPOk`.
