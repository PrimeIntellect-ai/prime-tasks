Responses headers are mutated by the aiohttp web.Response
### Describe the bug

I am actually not sure if it is a bug a not, but I am observed different behaviour when using global response headers starting from aiohttp 3.11.8.

After first call with `aiohttp/3.11.8+` aiohttp will mutate headers and store all information inside headers

```
web.Response(headers=default_headers)
```

```
<CIMultiDict('Content-Type': 'application/json; charset=utf-8', 'Content-Length': '1091', 'Date': 'Tue, 01 Apr 2025 13:00:28 GMT', 'Server': 'Python/3.13 aiohttp/3.11.15')>
```
And this will fail on the second response since content length was changed and now passed as incorrect value.

Contrary aiohttp 3.11.7 doesn't mutate default headers
```
<CIMultiDict('Content-Type': 'application/json')>
```

Workaround is to pass dict instead of CIMultiDict

### To Reproduce

```python
import asyncio
import json
import random

import aiohttp
from aiohttp import web, ClientSession
from multidict import CIMultiDict

default_headers = CIMultiDict({"Content-Type": "application/json"})

async def handle(request):
    print(aiohttp.__version__)
    print(default_headers)
    return web.Response(
        text=json.dumps({"message": random.randbytes(random.randint(1, 1000)).hex()}),
        headers=default_headers
    )

async def run_server():
    app = web.Application()
    app.router.add_get("/", handle)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "localhost", 8080)
    await site.start()

async def run_client():
    async with ClientSession() as session:
        for i in range(10):
            await asyncio.sleep(1)

            async with session.get("http://localhost:8080") as resp:
                print(await resp.json())

async def main():
    server_task = asyncio.create_task(run_server())
    client_task = asyncio.create_task(run_client())
    await client_task  # Run client once
    server_task.cancel()  # Stop server

if __name__ == "__main__":
    asyncio.run(main())
```

### Expected behavior

-

### Logs/tracebacks

```python-traceback
3.11.15
<CIMultiDict('Content-Type': 'application/json')>
{'message': '7fd6a48fe3d8'}
3.11.15
<CIMultiDict('Content-Type': 'application/json; charset=utf-8', 'Content-Length': '1763', 'Date': 'Tue, 01 Apr 2025 13:08:07 GMT', 'Server': 'Python/3.13 aiohttp/3.11.15')>
Traceback (most recent call last):
  File "/src/auth/.venv/lib/python3.13/site-packages/aiohttp/client_proto.py", line 264, in data_received
    messages, upgraded, tail = self._parser.feed_data(data)
                               ~~~~~~~~~~~~~~~~~~~~~~^^^^^^
  File "aiohttp/_http_parser.pyx", line 558, in aiohttp._http_parser.HttpParser.feed_data
aiohttp.http_exceptions.BadHttpMessage: 400, message:
  Expected HTTP/:

    b'{
```

### Python Version

```console
$ python --version
Python 3.13.2
```

### aiohttp Version

```console
$ python -m pip show aiohttp
Name: aiohttp
Version: 3.11.15
```

### multidict Version

```console
$ python -m pip show multidict
Name: multidict
Version: 6.3.0
```

### propcache Version

```console
$ python -m pip show propcache
Name: propcache
Version: 0.3.1
```

### yarl Version

```console
$ python -m pip show yarl
Name: yarl
Version: 1.18.3
```

### OS

macOs

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct
