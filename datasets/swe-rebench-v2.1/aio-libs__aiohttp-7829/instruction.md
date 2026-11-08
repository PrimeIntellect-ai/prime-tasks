UrlDispatcher improvements
### Describe the bug

The UrlDispatcher currently has to do a linear search to dispatch urls which has an average time complexity of `O(n)`. This means that urls that are registered first can be found faster than urls that are registered later.


### To Reproduce

Results
```
% python3 url_dispatcher.py
resolve_time_first_url: 0.0017513339989818633
resolve_time_last_url: 2.258735582989175
```

This can be demonstrated with the following benchmark script
```python
import asyncio
import timeit
from unittest.mock import MagicMock, AsyncMock

from yarl import URL

from aiohttp import web
from aiohttp.web_urldispatcher import (
    UrlDispatcher,
)

URL_COUNT = 5000


async def url_dispatcher_performance():
    """Filter out large cookies from the cookie jar."""
    dispatcher = UrlDispatcher()
    for i in range(URL_COUNT):
        dispatcher.add_get(f"/static/sub/path{i}", AsyncMock())

    first_url = "/static/sub/path0"
    last_url = f"/static/sub/path{URL_COUNT-1}"

    request_first_url = web.Request(
        MagicMock(url=URL(first_url), method="GET"),
        MagicMock(),
        protocol=MagicMock(),
        host="example.com",
        task=MagicMock(),
        loop=asyncio.get_running_loop(),
        payload_writer=MagicMock(),
    )
    match_info = await dispatcher.resolve(request_first_url)
    assert match_info.route.resource.canonical == first_url

    request_last_url = web.Request(
        MagicMock(url=URL(last_url), method="GET"),
        MagicMock(),
        protocol=MagicMock(),
        host="example.com",
        task=MagicMock(),
        loop=asyncio.get_running_loop(),
        payload_writer=MagicMock(),
    )
    match_info = await dispatcher.resolve(request_last_url)
    assert match_info.route.resource.canonical == last_url

    async def resolve_times(request: web.Request, times: int) -> float:
        start = timeit.default_timer()
        for _ in range(times):
            await dispatcher.resolve(request)
        end = timeit.default_timer()
        return end - start

    run_count = 2000
    resolve_time_first_url = await resolve_times(request_first_url, run_count)
    resolve_time_last_url = await resolve_times(request_last_url, run_count)
    print(f"resolve_time_first_url: {resolve_time_first_url}")
    print(f"resolve_time_last_url: {resolve_time_last_url}")


asyncio.run(url_dispatcher_performance())

```

### Expected behavior

Ideally the time complexity is at most `O(url_parts)`

### Logs/tracebacks

```python-traceback
n/a
```


### Python Version

```console
n/a
```


### aiohttp Version

```console
master
```


### multidict Version

```console
n/a
```


### yarl Version

```console
n/a
```


### OS

n/a

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- A fixed/static path is always preferred over a dynamic/variable path.
  For example, given the routes ``/a/b`` and ``/a/{name}``, a request for
  ``/a/b`` resolves to ``/a/b``.
- When several dynamic routes could match a request, the route with the
  longest fixed prefix is preferred. If several dynamic routes share the
  same fixed prefix, they are resolved in order of registration.
