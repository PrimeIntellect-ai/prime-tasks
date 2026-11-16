WebSocket handlers may return an HTTP 204 response
Another one about WebSockets. :)

This PR #446, while fixing important things, introduced an interesting bug I didn't expect to happen.

Apparently, if a route handler has a return type of `None` (like a typical WebSocket handler does), its result will be replaced with an HTTP 204 response. This is really handy for HTTP routes, but now that we have this line in `Application._handle_websocket()` it may produce an error:

```python
try:
    return await route.handler(ws)  # This line returns HTTP 204.
except Exception as exc:
    ...
```

The error goes like `ASGI callable should return None, but returned '<Response 204>'.`

I see two ways to fix this:
1. The implicit one. Just do this and no one will be hurt.
```python
[HIDDEN]
```
2. The explicit one. Don't normalize handler's result to 204 if it's a WebSocket handler. Even more, ignore any result from a WebSocket handler and always return `None`. I guess it could be done in `_get_async_wrapper_for_output` like that:
```python
[HIDDEN]
```

I like the explicit one better. I could create a PR to fix this, but I'm not sure if this solution is indeed right (though it fixes the error message and passes the tests).
