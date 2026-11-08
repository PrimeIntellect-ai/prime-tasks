Resource reuse not working for dynamic resources
### Describe the bug

I am adding the same route several times with different method to an app. This worked fine, but I needed to add `name="request"` to be able to identify which route is going to be used in a custom middleware.This ends up in an error about registering a resource more than once.

When inspecting the code around `web_urldispatcher`, I think that it should normally be accepted by the server:

https://github.com/aio-libs/aiohttp/blob/a4ed8c56430bd44c4d7000cea20e62acaa4a2e8f/aiohttp/web_urldispatcher.py#L1056-L1060

[HIDDEN] But I think we should probably match these correctly, no?

### To Reproduce

```py
run_routes = [
    # Be aware that handling ANY_METHOD (*) conflicts with CORS preflight
    # since it needs to overtake the OPTIONS method. So we manually specify
    # all other methods (this is currently a bug in aiohttp-cors).
    #
    # https://github.com/aio-libs/aiohttp-cors/issues/241
    web.route(method, "/{path:.*}", self.on_request, name="request")
    for method in (
        "GET",
        "POST",
        "PUT",
        "DELETE",
        "PATCH",
    )
]
app.add_routes(run_routes)
```

### Expected behavior

it should reuse the resource instead of register a new one and failing

### Logs/tracebacks

```python-traceback
app.add_routes(run_routes)
  File "/.../python3.11/site-packages/aiohttp/web_app.py", line 334, in add_routes
    return self.router.add_routes(routes)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.../python3.11/site-packages/aiohttp/web_urldispatcher.py", line 1202, in add_routes
    registered_routes.extend(route_def.register(self))
                             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.../python3.11/site-packages/aiohttp/web_routedef.py", line 76, in register
    return [reg(self.path, self.handler, **self.kwargs)]
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.../python3.11/site-packages/aiohttp/web_urldispatcher.py", line 1168, in add_post
    return self.add_route(hdrs.METH_POST, path, handler, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.../python3.11/site-packages/aiohttp/web_urldispatcher.py", line 1102, in add_route
    resource = self.add_resource(path, name=name)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/.../python3.11/site-packages/aiohttp/web_urldispatcher.py", line 1090, in add_resource
    self.register_resource(resource)
  File "/.../python3.11/site-packages/aiohttp/web_urldispatcher.py", line 1068, in register_resource
    raise ValueError(
ValueError: Duplicate 'request', already handled by <DynamicResource 'request'  /{path}>
```


### Python Version

```console
python --version
Python 3.11.0
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.8.5
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /.../python3.11/site-packages
Requires: aiosignal, async-timeout, attrs, charset-normalizer, frozenlist, multidict, yarl
Required-by: aiohttp-cors, auth0-python, cloud-sql-python-connector, isolate_controller, kubernetes-asyncio, pyjwt-key-fetcher
```


### multidict Version

```console
❯ python -m pip show multidict
Name: multidict
Version: 6.0.4
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /.../python3.11/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
❯ python -m pip show yarl

Name: yarl
Version: 1.9.2
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: /.../python3.11/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

```
❯ uname -a
Darwin MattBookAir.local 22.3.0 Darwin Kernel Version 22.3.0: Mon Jan 30 20:38:43 PST 2023; root:xnu-8792.81.3~2/RELEASE_ARM64_T8112 arm64
```

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- Registering routes with different methods that share the same name and dynamic path, including a path with a regex pattern such as `/{path:.*}`, must reuse the resource instead of raising a duplicate-registration error.
