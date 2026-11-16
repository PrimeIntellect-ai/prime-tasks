absolute-form URIs are not validated
### Describe the bug

AIOHTTP parses request URIs like this: (from `aiohttp/http_parser.py:561-584`)
```python3
        if method == "CONNECT":
            # authority-form,
            # https://datatracker.ietf.org/doc/html/rfc7230#section-5.3.3
            url = URL.build(authority=path, encoded=True)
        elif path.startswith("/"):
            # origin-form,
            # https://datatracker.ietf.org/doc/html/rfc7230#section-5.3.1
            path_part, _hash_separator, url_fragment = path.partition("#")
            path_part, _question_mark_separator, qs_part = path_part.partition("?")

            # NOTE: `yarl.URL.build()` is used to mimic what the Cython-based
            # NOTE: parser does, otherwise it results into the same
            # NOTE: HTTP Request-Line input producing different
            # NOTE: `yarl.URL()` objects
            url = URL.build(
                path=path_part,
                query_string=qs_part,
                fragment=url_fragment,
                encoded=True,
            )
        [HIDDEN]
```
In short, if the URI is not an absolute path, and also not in a `CONNECT` request, then it is guessed to be in absolute-form. Whether the URI is truly in absolute-form is never verified. This causes some invalid requests to be accepted.

For example, the following request has a URI that doesn't match any of the URI forms in RFC 9112, but AIOHTTP still parses it because the URI is assumed to be in absolute form:
```
GET ! HTTP/1.1\r\n
\r\n
```
RFC 9112 suggests that we respond 400:
> When a server listening only for HTTP request messages, or processing what appears from the start-line to be an HTTP request message, receives a sequence of octets that does not match the HTTP-message grammar aside from the robustness exceptions listed above, the server SHOULD respond with a 400 (Bad Request) response and close the connection.

### To Reproduce

1. Start an AIOHTTP server (with AIOHTTP_NO_EXTENSIONS=1)
2. Send it a request with a URI of "!"

### Expected behavior

A 400 response.

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

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
