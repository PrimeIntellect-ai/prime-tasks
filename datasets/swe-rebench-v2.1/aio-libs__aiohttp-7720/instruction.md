Server using Python parser responds 500 for invalid Unicode in header
### Describe the bug

When an AIOHTTP server receives a request containing an invalid header, it formulates a response that echos the invalid header back to the user.

Something like this:
```
printf 'GET / HTTP/1.1\r\nI am invalid!!\r\n\r\n' | nc localhost 8080
```
gets a response like this:
```
HTTP/1.0 400 Bad Request
Content-Type: text/plain; charset=utf-8
Content-Length: 35
Date: Mon, 16 Oct 2023 19:27:30 GMT
Server: Python/3.11 aiohttp/4.0.0a2.dev0

Invalid HTTP Header: I am invalid!!
```

If the invalid header contains dangling UTF-8 surrogates, then the server is unable to encode the received bytes into Unicode, so the default error handler fails, and the server instead responds 500.

For example, something like this:
```
printf 'GET / HTTP/1.1\r\n\xff\r\n\r\n' | nc localhost 8080
```
gets a response like this:
```
HTTP/1.0 500 Internal Server Error
Content-Type: text/plain; charset=utf-8
Content-Length: 55
Date: Mon, 16 Oct 2023 19:26:29 GMT
Server: Python/3.11 aiohttp/4.0.0a2.dev0

500 Internal Server Error

Server got itself in trouble
```

### To Reproduce

0. Install aiohttp
1. Start the example server:
```
export AIOHTTP_NO_EXTENSIONS=1
python3 examples/server_simple.py
```
2. Send it a request:
```
printf 'GET / HTTP/1.1\r\n\xff\r\n\r\n' | nc localhost 8080
```
3. Observe that it responds 500:
```
HTTP/1.0 500 Internal Server Error
Content-Type: text/plain; charset=utf-8
Content-Length: 55
Date: Mon, 16 Oct 2023 19:33:03 GMT
Server: Python/3.11 aiohttp/4.0.0a2.dev0

500 Internal Server Error

Server got itself in trouble
```

### Expected behavior

The server should have responded 400.

### Logs/tracebacks

```python-traceback
======== Running on http://0.0.0.0:8080 ========
(Press CTRL+C to quit)
Error handling request
Traceback (most recent call last):
  File "/home/bkallus/clones/aiohttp/aiohttp/web_protocol.py", line 366, in data_received
    messages, upgraded, tail = self._request_parser.feed_data(data)
                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/http_parser.py", line 314, in feed_data
    msg: _MsgT = self.parse_message(self._lines)
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/http_parser.py", line 601, in parse_message
    ) = self.parse_headers(lines)
        ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/http_parser.py", line 466, in parse_headers
    headers, raw_headers = self._headers_parser.parse_headers(lines)
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/http_parser.py", line 139, in parse_headers
    raise InvalidHeader(line) from None
aiohttp.http_exceptions.InvalidHeader: 400, message:
  Invalid HTTP Header: \udcff
Error handling request
Traceback (most recent call last):
  File "/home/bkallus/clones/aiohttp/aiohttp/web_protocol.py", line 468, in _handle_request
    resp = await request_handler(request)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/web_protocol.py", line 707, in handler
    return self.handle_error(
           ^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/web_protocol.py", line 698, in handle_error
    resp = Response(status=status, text=message, content_type=ct)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/bkallus/clones/aiohttp/aiohttp/web_response.py", line 539, in __init__
    body = text.encode(charset)
           ^^^^^^^^^^^^^^^^^^^^
UnicodeEncodeError: 'utf-8' codec can't encode character '\udcff' in position 21: surrogates not allowed
```


### Python Version

```console
$ python --version
Python 3.11.5
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
Location: /home/bkallus/clones/aiohttp/env/lib/python3.11/site-packages
Editable project location: /home/bkallus/clones/aiohttp
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
Location: /home/bkallus/clones/aiohttp/env/lib/python3.11/site-packages
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
Location: /home/bkallus/clones/aiohttp/env/lib/python3.11/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

Arch Linux (Linux 6.1.56-1-lts)

### Related component

Server

### Additional context

This bug (as with the others I've found) was discovered by differential fuzzing against a Node-based HTTP server.

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- For `aiohttp.http_exceptions.InvalidHeader("X-Spam")`, `message` must be exactly `Invalid HTTP header: 'X-Spam'`, `str(err)` must be exactly `400, message:\n  Invalid HTTP header: 'X-Spam'`, and `repr(err)` must be exactly `<InvalidHeader: 400, message="Invalid HTTP header: 'X-Spam'">`.
- When the Python HTTP request parser receives `b"POST / HTTP/1.1\r\n\xff\r\n\r\n"`, parsing must raise `aiohttp.http_exceptions.InvalidHeader`, whose `message` is encodable with UTF-8.
