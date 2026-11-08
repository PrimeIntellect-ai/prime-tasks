Server certificate fingerprint is not verified when request through http proxy
### Describe the bug

When making request as below to try to verify server certificate fingerprint 'digest' during http request:

```
tcp_connector = TCPConnector(ssl=aiohttp.Fingerprint(digest))
async with aiohttp.ClientSession(headers=headers, connector=tcp_connector, trust_env=True) as session:
    async with session.request(...) as r:
        ....
```

If the request go directly to the server, the server fingerprint is verified successfully: when the 'digest' matches the server certificate fingerprint digest, the request succeed, when it doesn't match, a 'aiohttp.ServerFingerprintMismatch' exception is thrown.
While if the request need to go through a http proxy (with env: HTTP_PROXY, HTTPS_PROXY set as the proxy), the server fingerprint is not verified: whether the 'digest' matches the server certificate fingerprint digest or not, the request will always succeed, no 'aiohttp.ServerFingerprintMismatch' exception is thrown.

### To Reproduce

1. setup a "http server" and a "http proxy" through which the "http server" can be requested.
2. write a simple program as above:
```
tcp_connector = TCPConnector(ssl=aiohttp.Fingerprint(digest))
async with aiohttp.ClientSession(headers=headers, connector=tcp_connector) as session:
    async with session.request(...) as r:
        ....
```
set the 'digest' as a mismatch one as the http server's certificate fingerprint digest
3. the request can be made successfully

### Expected behavior

The request should fail with a 'aiohttp.ServerFingerprintMismatch' exception.

### Logs/tracebacks

```python-traceback
NONE
```


### Python Version

```console
$ python3 -V
Python 3.8.10
```


### aiohttp Version

```console
$ python3 -m pip show aiohttp
Name: aiohttp
Version: 3.8.1
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /usr/local/lib/python3.8/dist-packages
Requires: aiosignal, multidict, frozenlist, attrs, charset-normalizer, async-timeout, yarl
Required-by: uniconlib, aiohttp-jinja2
```


### multidict Version

```console
$ python3 -m pip show multidict
Name: multidict
Version: 6.0.2
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /usr/local/lib/python3.8/dist-packages
Requires:
Required-by: yarl, aiohttp
```


### yarl Version

```console
$ python3 -m pip show yarl
Name: yarl
Version: 1.7.2
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /usr/local/lib/python3.8/dist-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

$ cat /etc/issue
Ubuntu 20.04.4 LTS \n \l


### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- An HTTPS request routed through an HTTP proxy must be allowed when the server certificate fingerprint matches.
