Memory Leak Due to Cyclic References in Traceback
### Describe the bug

A potential memory leak has been observed in aiohttp when handling streaming responses. The following script reproduces the issue by continuously reading a response stream from an aiohttp server. After the client disconnects due to ServerDisconnectedError, garbage collection (gc) still reports lingering ClientResponse objects, suggesting a resource leak due to cyclic references in traceback objects.

### To Reproduce

1. Run the following script.
2. Observe the output for lingering ClientResponse objects, which are visualized using objgraph.

```python

import asyncio
import aiohttp
from aiohttp import web
import gc
from time import time
import objgraph

gc.set_debug(gc.DEBUG_LEAK)


def get_garbage():
    result = []
    gc.collect()
    for obj in gc.garbage:
        obj_name = type(obj).__name__
        result.append(f'{obj_name}')
        if obj_name in ('ClientResponse',):
            print('ClientResponse not collected!')
            objgraph.show_backrefs(
                obj,
                max_depth=30,
                too_many=50,
                filename=f"/tmp/{int(time() * 1000)}err_referrers.png",
            )

    return result


class Client:
    def __init__(self):
        self.session = aiohttp.ClientSession()
        self.response = None

    async def fetch_stream(self, url):
        try:
            self.response = await self.session.get(url)
            if self.response.status == 200:
                while True:
                    chunk = await self.response.content.readexactly(6)
                    print(f'received: {chunk.decode().strip()}')
            else:
                print(f'response status code: {self.response.status}')
        except (
            aiohttp.ClientConnectorError,
            aiohttp.ServerDisconnectedError,
            aiohttp.ClientPayloadError,
            asyncio.IncompleteReadError
        ) as e:
            print(f'connection error ({type(e).__name__})')
        except Exception as e:
            print(f'unexpected error: {e}')
        finally:
            self.response = None  # Explicitly clear response
            self.session = None  # This should close the session, but memory leak persists due to traceback references.


async def stream_handler(request):
    writer = request.transport
    if writer:
        writer.close()  # Forcefully closing connection

    return web.Response()


async def main():
    app = web.Application()
    app.router.add_get('/stream', stream_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, 'localhost', 8080)
    await site.start()

    client = Client()
    client_task = asyncio.create_task(client.fetch_stream('http://localhost:8080/stream'))

    await client_task
    await asyncio.sleep(0.5)  # Allow time for cleanup

    print(f'Garbage objects: {get_garbage()}')

    await runner.cleanup()


if __name__ == '__main__':
    asyncio.run(main())
```

### Expected behavior

* ClientResponse should be properly garbage collected after the session is closed.
* No lingering references should prevent cleanup.

### Logs/tracebacks

```python-traceback
Observe the output for lingering ClientResponse objects, which are visualized using objgraph.
```

### Python Version

```console
3.12.9
```

### aiohttp Version

```console
3.11.11
```

### multidict Version

```console
6.1.0
```

### propcache Version

```console
0.2.0
```

### yarl Version

```console
1.17.1
```

### OS

Ubuntu 22.04.5 LTS

### Related component

Client

### Additional context

**Fixed Version FixClientResponse (Memory Leak Resolved)**

```python
import asyncio
import aiohttp
from aiohttp import web
import gc
from time import time
import objgraph

gc.set_debug(gc.DEBUG_LEAK)

def get_garbage():
    result = []
    gc.collect()
    for obj in gc.garbage:
        obj_name = type(obj).__name__
        result.append(f'{obj_name}')
        if obj_name in ('ClientResponse',):
            objgraph.show_backrefs(
                obj,
                max_depth=30,
                too_many=50,
                filename=f"/tmp/{int(time() * 1000)}err_referrers.png",
            )

    return result


[HIDDEN]


class Client:
    def __init__(self):
        self.session = aiohttp.ClientSession(response_class=FixClientResponse)
        self.response = None

    async def fetch_stream(self, url):
        try:
            self.response = await self.session.get(url)
            if self.response.status == 200:
                while True:
                    chunk = await self.response.content.readexactly(6)
                    print(f'received: {chunk.decode().strip()}')
            else:
                print(f'response status code: {self.response.status}')
        except (
            aiohttp.ClientConnectorError,
            aiohttp.ServerDisconnectedError,
            aiohttp.ClientPayloadError,
            asyncio.IncompleteReadError
        ) as e:
            print(f'connection error ({type(e).__name__})')
        except Exception as e:
            print(f'unexpected error: {e}')
        finally:
            self.response = None
            self.session = None


async def stream_handler(request):
    writer = request.transport
    if writer:
        writer.close()  # Forcefully closing connection

    return web.Response()


async def main():
    app = web.Application()
    app.router.add_get('/stream', stream_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, 'localhost', 8080)
    await site.start()

    client = Client()
    client_task = asyncio.create_task(client.fetch_stream('http://localhost:8080/stream'))

    await client_task
    await asyncio.sleep(0.5)  # Allow time for cleanup

    print(f'Garbage objects: {get_garbage()}')

    await runner.cleanup()


if __name__ == '__main__':
    asyncio.run(main())
```

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- After the session is closed, the response must be released without requiring the cyclic garbage collector to run.
