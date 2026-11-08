bug: `AttributeError`: `close()` called on Service dependency in `TestClient`
### Describe the bug

Hi,

I am encountering `AttributeError` when using `TestClient` due to `close` being called on service dependencies. Below is the reproducible example.

In the documentation, a simple service is demoed. But this doesn't work with model composition.
https://docs.bentoml.com/en/latest/guides/testing.html#http-behavior-tests

I believe this is linked to using `TestClient` as a context manager calls the lifespan handler.
https://www.starlette.io/lifespan/#running-lifespan-in-tests

The service file
```
# service.py

import bentoml


@bentoml.service(metrics={"enabled": False})
class Model:
    model = {"hello": "world"}

    @bentoml.api()
    def get(self, key: str) -> str | None:
        return self.model.get(key)

    # workaround: add close method in dependent model
    # async def close(self) -> None:
    #     pass


@bentoml.service(metrics={"enabled": False})
class Service:
    model = bentoml.depends(Model)

    @bentoml.api()
    def get(self, key: str) -> dict[str, str | None]:
        return {"value": self.model.get(key)}
```

Using `TestClient` directly on the `Model` is fine.
```
# test model

from starlette.testclient import TestClient

from service import Model


with TestClient(app=Model.to_asgi()) as client:
    resp = client.post("/get", json={"key": "hello"})
    print(resp.text)
    resp.raise_for_status()

# output: world
```

But using `TestClient` on `Service` throws `AttributeError`. Stack trace is below.
```
# test service

from starlette.testclient import TestClient

from service import Service


with TestClient(app=Service.to_asgi()) as client:
    resp = client.post("/get", json={"key": "hello"})
    print(resp.text)
    resp.raise_for_status()

# output: {"value": "world"}
# also attribute error is thrown on exiting the client context manager

Traceback (most recent call last):
  File "project/test_service.py", line 5, in <module>
    with TestClient(app=Service.to_asgi()) as client:
  File "venv/lib/python3.10/site-packages/starlette/testclient.py", line 750, in __exit__
    self.exit_stack.close()
  File "venv/lib/python3.10/contextlib.py", line 584, in close
    self.__exit__(None, None, None)
  File "venv/lib/python3.10/contextlib.py", line 576, in __exit__
    raise exc_details[1]
  File "venv/lib/python3.10/contextlib.py", line 153, in __exit__
    self.gen.throw(typ, value, traceback)
  File "venv/lib/python3.10/site-packages/anyio/from_thread.py", line 495, in start_blocking_portal
    yield portal
  File "venv/lib/python3.10/contextlib.py", line 561, in __exit__
    if cb(*exc_details):
  File "venv/lib/python3.10/contextlib.py", line 449, in _exit_wrapper
    callback(*args, **kwds)
  File "venv/lib/python3.10/site-packages/starlette/testclient.py", line 743, in wait_shutdown
    portal.call(self.wait_shutdown)
  File "venv/lib/python3.10/site-packages/anyio/from_thread.py", line 290, in call
    return cast(T_Retval, self.start_task_soon(func, *args).result())
  File "venv/lib/python3.10/concurrent/futures/_base.py", line 458, in result
    return self.__get_result()
  File "venv/lib/python3.10/concurrent/futures/_base.py", line 403, in __get_result
    raise self._exception
  File "venv/lib/python3.10/site-packages/anyio/from_thread.py", line 221, in _call_func
    retval = await retval_or_awaitable
  File "venv/lib/python3.10/site-packages/starlette/testclient.py", line 791, in wait_shutdown
    await receive()
  File "venv/lib/python3.10/site-packages/starlette/testclient.py", line 780, in receive
    self.task.result()
  File "venv/lib/python3.10/concurrent/futures/_base.py", line 451, in result
    return self.__get_result()
  File "venv/lib/python3.10/concurrent/futures/_base.py", line 403, in __get_result
    raise self._exception
  File "venv/lib/python3.10/site-packages/anyio/from_thread.py", line 221, in _call_func
    retval = await retval_or_awaitable
  File "venv/lib/python3.10/site-packages/starlette/testclient.py", line 755, in lifespan
    await self.app(scope, self.stream_receive.receive, self.stream_send.send)
  File "venv/lib/python3.10/site-packages/starlette/applications.py", line 113, in __call__
    await self.middleware_stack(scope, receive, send)
  File "venv/lib/python3.10/site-packages/starlette/middleware/errors.py", line 152, in __call__
    await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/opentelemetry/instrumentation/asgi/__init__.py", line 543, in __call__
    return await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/bentoml/_internal/server/http/access.py", line 69, in __call__
    await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/bentoml/_internal/server/http/traffic.py", line 26, in __call__
    return await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/_bentoml_impl/server/app.py", line 62, in __call__
    return await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/starlette/middleware/exceptions.py", line 48, in __call__
    await self.app(scope, receive, send)
  File "venv/lib/python3.10/site-packages/starlette/routing.py", line 715, in __call__
    await self.middleware_stack(scope, receive, send)
  File "venv/lib/python3.10/site-packages/starlette/routing.py", line 724, in app
    await self.lifespan(scope, receive, send)
  File "venv/lib/python3.10/site-packages/starlette/routing.py", line 693, in lifespan
    async with self.lifespan_context(app) as maybe_state:
  File "venv/lib/python3.10/contextlib.py", line 206, in __aexit__
    await anext(self.gen)
  File "venv/lib/python3.10/site-packages/bentoml/_internal/server/base_app.py", line 81, in lifespan
    await ret
  File "venv/lib/python3.10/site-packages/_bentoml_impl/server/app.py", line 329, in destroy_instance
    await cleanup()
  File "venv/lib/python3.10/site-packages/_bentoml_sdk/service/dependency.py", line 26, in cleanup
    await asyncio.gather(*tasks)
  [HIDDEN]
AttributeError: 'Model' object has no attribute 'close'
```

A possible workaround is to add an empty async `close` method to the dependent model as I added as a comment. I think this should be better handled in the `bentoml.depends` decorator instead.

### To reproduce

Example as provided above.

### Expected behavior

`AttributeError` should not be thrown when using `TestClient` on service with model composition.

### Environment

`bentoml==1.3.11`
`python==3.10.13`

platform: ubuntu 22.04

### Additional contract requirements

- Exiting a `TestClient` context for a service with a dependency that does not define `close()` must not raise `AttributeError` during shutdown.
