When the client sends a relatively large bytes data packet to the server, the server will receive zero length message.
### Describe the bug

If the client sends a 20M bytes message, the server will receive zero length message.

The 3.11.16 version works fine.

### To Reproduce

1. Start a WebSocket server, when a request is received, create a WebSocket object "ws = web.WebSocketResponse(max_msg_size = 0)"
2. await ws.prepare(request)
3. await ws.receive_bytes()
4. At this point, if the client sends a 20M bytes message, the server will get zero length message. Setting max_msg_size to 100M yields the same result.

### Expected behavior

Receive correct message.


### Logs/tracebacks

```python-traceback
No exception, but error message.
```

### Python Version

```console
$ python --version
3.11.2
```

### aiohttp Version

```console
$ python -m pip show aiohttp
3.11.17
```

### multidict Version

```console
$ python -m pip show multidict
6.0.4
```

### propcache Version

```console
$ python -m pip show propcache
0.2.0
```

### yarl Version

```console
$ python -m pip show yarl
1.18.3
```

### OS

Linux, debian 12

### Related component

Server

### Additional context

```python
from aiohttp import web

async def Handler(request: web.Request):
    try:
        ws = web.WebSocketResponse(max_msg_size=100*1024*1024)
        await ws.prepare(request)
        while True:
            rawMsg = await ws.receive_bytes()
            print(len(rawMsg))
            await ws.send_bytes(rawMsg)
    except BaseException as e:
        print(e)


if __name__ == "__main__":
    app = web.Application()
    app.add_routes([web.get("/get_task", Handler)])
    web.run_app(app, path="./test_websocket.socket", handle_signals=False)
```

Client

### Additional context
```python
import asyncio
import aiohttp
import pickle

async def Main():
    async with aiohttp.ClientSession(
        connector=aiohttp.UnixConnector("./test_websocket.socket")
    ) as client:
        while True:
            try:
                async with client.ws_connect("ws://xxxxx/get_task", max_msg_size=0) as ws:

                    async def RecvTask():
                        while True:
                            rawMsg = await ws.receive_bytes()
                            print(len(rawMsg))

                    async def SendTask():
                        while True:
                            await ws.send_bytes(pickle.dumps([{"aa": 123}]*10000000))
                            await asyncio.sleep(5)

                    await asyncio.gather(RecvTask(), SendTask())
            except BaseException as e:
                print(f"{e!r}")
                await asyncio.sleep(10)


if __name__ == "__main__":
    asyncio.run(Main())
```

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct
