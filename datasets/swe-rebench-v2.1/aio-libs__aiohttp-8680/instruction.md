WebSocketResponse.close code/message don't reach the client
## Long story short

Following this example from the docs
https://docs.aiohttp.org/en/stable/web_advanced.html?highlight=going_away#graceful-shutdown

The code and message passed to `ws.close` don't reach the client side and instead, a default code and message is used.

## Expected behaviour

I would expect that the code and message should reach the client.
If I'm wrong, the documentation could explain why this is not the case.

## Actual behaviour

Default code and message are returned (`code=1000, message=b''`)

## Steps to reproduce

The commented-out asserts fail.

```python
import weakref

import aiohttp.http
import aiohttp.web


async def websocket_handler(request):
    websocket = aiohttp.web.WebSocketResponse()
    await websocket.prepare(request)
    request.app["websockets"].add(websocket)

    try:
        async for message in websocket:
            await websocket.send_json({"ok": True, "message": message.json()})
    finally:
        request.app["websockets"].discard(websocket)

    return websocket


async def on_shutdown(app):
    for websocket in set(app["websockets"]):
        await websocket.close(
            code=aiohttp.WSCloseCode.GOING_AWAY,
            message="Server shutdown",
        )


async def test_foo(aiohttp_client):
    url = "/ws"
    app = aiohttp.web.Application()
    app["websockets"] = weakref.WeakSet()
    app.router.add_get(url, websocket_handler)
    app.on_shutdown.append(on_shutdown)

    client = await aiohttp_client(app)

    websocket = await client.ws_connect(url)

    message = {"message": "hi"}
    await websocket.send_json(message)
    reply = await websocket.receive_json()
    assert reply == {"ok": True, "message": message}

    await app.shutdown()

    assert websocket.closed is False

    reply = await websocket.receive()

    assert reply.type == aiohttp.http.WSMsgType.CLOSE
    assert reply.data == aiohttp.WSCloseCode.OK
    assert reply.extra == ""
    # assert reply.data == aiohttp.WSCloseCode.GOING_AWAY
    # assert reply.extra == "Server shutdown"
    assert websocket.closed is True
```

## Your environment

Python 3.6.7

```
aiohttp==3.4.4
pytest==4.0.1
pytest-aiohttp==0.3.0
```
