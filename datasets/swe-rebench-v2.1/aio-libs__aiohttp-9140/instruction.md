3.9.2 server keep-alive timeout can cause disconnect of active connections and hence client server disconnect errors
### Describe the bug

as mentioned in https://github.com/aio-libs/aiohttp/issues/2682 we had an issue with keep-alive timeouts.  There appears to be a race condition between how often requests are made and the server keep alive timeout.  If they overlap often the server will cause disconnect errors on the client.

### To Reproduce

Running the following code in 3.9.2/3.10.5:
```python
import asyncio
import random
import sys
import logging
import time

import aiohttp
import aiohttp.web
import requests
import requests.adapters

logger = logging.getLogger()


async def get_foo(req: aiohttp.web.Request):
    response = aiohttp.web.StreamResponse(status=200, headers={'Content-Type': 'text/csv'})

    logger.info("sending response")
    await response.prepare(req)
    await response.write(b'abc' * 512)
    # await asyncio.sleep(1)
    await response.write_eof()
    logger.info("wrote eof")
    return response


port = int(sys.argv[1])

async def server():
    app = aiohttp.web.Application()
    app.add_routes([aiohttp.web.get('/foo', get_foo)])
    await aiohttp.web._run_app(app, port=port, keepalive_timeout=1.0)


async def aiohttp_client(session: aiohttp.ClientSession):
    while True:
        async with session.get(f'http://localhost:{port}/foo', verify_ssl=False) as r:
            result = await r.text()
            logger.info(f'{result[:15]}...')

        await asyncio.sleep(random.uniform(0.99, 1.01))


def requests_client(session):
    while True:
        res = session.get(f'http://localhost:{port}/foo', verify=False)
        result = res.text
        logger.info(f'{result[:15]}...')
        time.sleep(random.uniform(0.99, 1.01))


async def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)-8s %(message)s')
    server_task = asyncio.create_task(server())

    num_clients = 4
    await asyncio.sleep(2)

    loop = asyncio.get_event_loop()

    session = requests.Session()
    session.mount("https://", requests.adapters.HTTPAdapter(pool_connections=num_clients, pool_maxsize=num_clients))
    session.mount("http://", requests.adapters.HTTPAdapter(pool_connections=num_clients, pool_maxsize=num_clients))
    await loop.run_in_executor(None, requests_client, session)

    # connector = aiohttp.TCPConnector(limit=num_clients, limit_per_host=num_clients)
    # async with aiohttp.ClientSession(connector=connector) as session:
        # await asyncio.gather(*(aiohttp_client(session) for _ in range(num_clients)))

    await server_task

if __name__ == '__main__':
    asyncio.run(main())
```

In 3.9.2 you'll get errors like:
```
2024-09-12 18:25:05,528 INFO     sending response
2024-09-12 18:25:05,529 INFO     abcabcabcabcabc...
2024-09-12 18:25:05,530 INFO     wrote eof
2024-09-12 18:25:05,530 INFO     ::1 [12/Sep/2024:17:25:05 -0800] "GET /foo HTTP/1.1" 200 1691 "-" "python-requests/2.32.3"
Traceback (most recent call last):
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connectionpool.py", line 789, in urlopen
    response = self._make_request(
               ^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connectionpool.py", line 536, in _make_request
    response = conn.getresponse()
               ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connection.py", line 464, in getresponse
    httplib_response = super().getresponse()
                       ^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 1395, in getresponse
    response.begin()
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 325, in begin
    version, status, reason = self._read_status()
                              ^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 286, in _read_status
    line = str(self.fp.readline(_MAXLINE + 1), "iso-8859-1")
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/socket.py", line 706, in readinto
    return self._sock.recv_into(b)
           ^^^^^^^^^^^^^^^^^^^^^^^
ConnectionResetError: [Errno 54] Connection reset by peer

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/requests/adapters.py", line 667, in send
    resp = conn.urlopen(
           ^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connectionpool.py", line 843, in urlopen
    retries = retries.increment(
              ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/util/retry.py", line 474, in increment
    raise reraise(type(error), error, _stacktrace)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/util/util.py", line 38, in reraise
    raise value.with_traceback(tb)
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connectionpool.py", line 789, in urlopen
    response = self._make_request(
               ^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connectionpool.py", line 536, in _make_request
    response = conn.getresponse()
               ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/urllib3/connection.py", line 464, in getresponse
    httplib_response = super().getresponse()
                       ^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 1395, in getresponse
    response.begin()
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 325, in begin
    version, status, reason = self._read_status()
                              ^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 286, in _read_status
    line = str(self.fp.readline(_MAXLINE + 1), "iso-8859-1")
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/socket.py", line 706, in readinto
    return self._sock.recv_into(b)
           ^^^^^^^^^^^^^^^^^^^^^^^
urllib3.exceptions.ProtocolError: ('Connection aborted.', ConnectionResetError(54, 'Connection reset by peer'))

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 71, in <module>
    asyncio.run(main())
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 190, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/base_events.py", line 654, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 64, in main
    await loop.run_in_executor(None, requests_client, session)
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 46, in requests_client
    res = session.get(f'http://localhost:{port}/foo', verify=False)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/requests/sessions.py", line 602, in get
    return self.request("GET", url, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/requests/sessions.py", line 589, in request
    resp = self.send(prep, **send_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/requests/sessions.py", line 703, in send
    r = adapter.send(request, **kwargs)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages/requests/adapters.py", line 682, in send
    raise ConnectionError(err, request=request)
requests.exceptions.ConnectionError: ('Connection aborted.', ConnectionResetError(54, 'Connection reset by peer'))

```

Running with 3.10.5:
```
024-09-12 18:27:06,597 INFO     sending response
2024-09-12 18:27:06,599 INFO     wrote eof
2024-09-12 18:27:06,599 INFO     ::1 [12/Sep/2024:17:27:06 -0800] "GET /foo HTTP/1.1" 200 1692 "-" "python-requests/2.32.3"
2024-09-12 18:27:06,604 INFO     abcabcabcabcabc...
Traceback (most recent call last):
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connectionpool.py", line 789, in urlopen
    response = self._make_request(
               ^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connectionpool.py", line 536, in _make_request
    response = conn.getresponse()
               ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connection.py", line 507, in getresponse
    httplib_response = super().getresponse()
                       ^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 1395, in getresponse
    response.begin()
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 325, in begin
    version, status, reason = self._read_status()
                              ^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 294, in _read_status
    raise RemoteDisconnected("Remote end closed connection without"
http.client.RemoteDisconnected: Remote end closed connection without response

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/requests/adapters.py", line 667, in send
    resp = conn.urlopen(
           ^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connectionpool.py", line 843, in urlopen
    retries = retries.increment(
              ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/util/retry.py", line 474, in increment
    raise reraise(type(error), error, _stacktrace)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/util/util.py", line 38, in reraise
    raise value.with_traceback(tb)
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connectionpool.py", line 789, in urlopen
    response = self._make_request(
               ^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connectionpool.py", line 536, in _make_request
    response = conn.getresponse()
               ^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/urllib3/connection.py", line 507, in getresponse
    httplib_response = super().getresponse()
                       ^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 1395, in getresponse
    response.begin()
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 325, in begin
    version, status, reason = self._read_status()
                              ^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/http/client.py", line 294, in _read_status
    raise RemoteDisconnected("Remote end closed connection without"
urllib3.exceptions.ProtocolError: ('Connection aborted.', RemoteDisconnected('Remote end closed connection without response'))

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 73, in <module>
    asyncio.run(main())
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 190, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/asyncio/base_events.py", line 654, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 64, in main
    await loop.run_in_executor(None, requests_client, session)
  File "/opt/homebrew/Cellar/python@3.11/3.11.9/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/Library/Application Support/JetBrains/PyCharm2024.2/scratches/scratch.py", line 46, in requests_client
    res = session.get(f'http://localhost:{port}/foo', verify=False)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/requests/sessions.py", line 602, in get
    return self.request("GET", url, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/requests/sessions.py", line 589, in request
    resp = self.send(prep, **send_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/requests/sessions.py", line 703, in send
    r = adapter.send(request, **kwargs)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/requests/adapters.py", line 682, in send
    raise ConnectionError(err, request=request)
requests.exceptions.ConnectionError: ('Connection aborted.', RemoteDisconnected('Remote end closed connection without response'))
2024-09-12 18:27:07,631 ERROR    Task exception was never retrieved
future: <Task finished name='Task-59' coro=<RequestHandler.start() done, defined at ~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/aiohttp/web_protocol.py:493> exception=AssertionError()>
Traceback (most recent call last):
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/aiohttp/web_protocol.py", line 536, in start
    request = self._request_factory(message, payload, self, writer, handler)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/aiohttp/web_app.py", line 479, in _make_request
    return _cls(
           ^^^^^
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/aiohttp/web_request.py", line 841, in __init__
    super().__init__(*args, **kwargs)
  File "~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages/aiohttp/web_request.py", line 196, in __init__
    assert transport is not None
           ^^^^^^^^^^^^^^^^^^^^^
AssertionError
```

Note if you swap to the aiohttp 3.10.5 client I can't get it to reproduce.  I think it's because I saw something in a PR about server disconnects..so I think that's just hiding the underlying problem that the server is erroneously disconnecting the client.

### Expected behavior

there should not be any errors in either version.

### Logs/tracebacks

```python-traceback
(see above)
```


### Python Version

```console
Python 3.11.9
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.9.2
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: ~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by: aiobotocore, fbn-googleapi, fbn-pcdu-client3, fbn_auth_client, pytest-aiohttp

and

Name: aiohttp
Version: 3.10.5
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: ~/.local/share/virtualenvs/commodities-uyI3VCa_/lib/python3.11/site-packages
Requires: aiohappyeyeballs, aiosignal, attrs, frozenlist, multidict, yarl
Required-by: aiobotocore
```


### multidict Version

```console
Name: multidict
Version: 6.1.0
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: ~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
Name: yarl
Version: 1.9.9
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: ~/.local/share/virtualenvs/ag_data-HNY644fZ/lib/python3.11/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

Darwin amohr-TYQNW6P9KQ.fbn.org 23.6.0 Darwin Kernel Version 23.6.0: Mon Jul 29 21:14:30 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T6000 arm64

### Related component

Server, Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
