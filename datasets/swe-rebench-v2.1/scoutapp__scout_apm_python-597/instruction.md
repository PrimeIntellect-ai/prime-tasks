object has no attribute '__qualname__'
I am getting the following error when trying to enable the scout APM on a starlette application:
```
Traceback (most recent call last):
  File "/app/.heroku/python/lib/python3.8/site-packages/uvicorn/protocols/http/httptools_impl.py", line 391, in run_asgi
    result = await app(self.scope, self.receive, self.send)
  File "/app/.heroku/python/lib/python3.8/site-packages/uvicorn/middleware/proxy_headers.py", line 45, in __call__
    return await self.app(scope, receive, send)
  File "/app/.heroku/python/lib/python3.8/site-packages/starlette/applications.py", line 111, in __call__
    await self.middleware_stack(scope, receive, send)
  File "/app/.heroku/python/lib/python3.8/site-packages/starlette/middleware/errors.py", line 181, in __call__
    raise exc from None
  File "/app/.heroku/python/lib/python3.8/site-packages/starlette/middleware/errors.py", line 159, in __call__
    await self.app(scope, receive, _send)
  File "/app/.heroku/python/lib/python3.8/site-packages/scout_apm/async_/starlette.py", line 67, in __call__
    grab_extra_data()
  File "/app/.heroku/python/lib/python3.8/site-packages/scout_apm/async_/starlette.py", line 35, in grab_extra_data
    endpoint.__module__, endpoint.__qualname__
AttributeError: 'GraphQLWithBackground' object has no attribute '__qualname__'
```

`GraphQLWithBackground` is a subclass of `ariadne.asgi.GraphQL`.

### Additional contract requirements

- For a Starlette endpoint that is a class instance, Scout must record a controller span whose operation starts with `Controller/` and ends with `InstanceApp`.
