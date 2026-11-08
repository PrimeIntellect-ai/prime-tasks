TCPSite.name raises ValueError if host is empty string
### Describe the bug

`aiohttp` creates a TCP server by calling `loop.create_server()` in `TCPSite.start()`. The `loop.create_server()` function allows for empty string to be passed as `host` parameter, effectively binding the server socket to `INADDR_ANY`. Here's an extract from [docs](https://docs.python.org/3/library/asyncio-eventloop.html#creating-network-servers):

> If host is an empty string or None, all interfaces are assumed and a list of multiple sockets will be returned

So, creating an instance of `TCPSite` with `host=''` and calling `site.start()` works perfectly fine, however, getting `site.name` fails raising `ValueError: Can't build URL with "port" but without "host".`

Inadvertently this backfires when using `web.run_app()` (see below).

### To Reproduce

```
from aiohttp import web
app = web.Application()
web.run_app(app, host='', port=8080)
```

### Expected behavior

Since empty host virtually means bind to '0.0.0.0' (same as `host=None`) I expect `TCPSite.name` to return `"http://0.0.0.0:8080"`.

### Logs/tracebacks

```python-traceback
>>> from aiohttp import web
>>> app = web.Application()
>>> web.run_app(app, host='', port=8080)
unhandled exception during asyncio.run() shutdown
task: <Task finished name='Task-1' coro=<_run_app() done, defined at /Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py:287> exception=ValueError('Can\'t build URL with "port" but without "host".')>
Traceback (most recent call last):
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 514, in run_app
    loop.run_until_complete(main_task)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/asyncio/base_events.py", line 616, in run_until_complete
    return future.result()
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 416, in _run_app
    names = sorted(str(s.name) for s in runner.sites)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 416, in <genexpr>
    names = sorted(str(s.name) for s in runner.sites)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web_runner.py", line 114, in name
    return str(URL.build(scheme=scheme, host=host, port=self._port))
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/yarl/_url.py", line 216, in build
    raise ValueError('Can\'t build URL with "port" but without "host".')
ValueError: Can't build URL with "port" but without "host".
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 514, in run_app
    loop.run_until_complete(main_task)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/asyncio/base_events.py", line 616, in run_until_complete
    return future.result()
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 416, in _run_app
    names = sorted(str(s.name) for s in runner.sites)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web.py", line 416, in <genexpr>
    names = sorted(str(s.name) for s in runner.sites)
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/aiohttp/web_runner.py", line 114, in name
    return str(URL.build(scheme=scheme, host=host, port=self._port))
  File "/Library/Frameworks/Python.framework/Versions/3.8/lib/python3.8/site-packages/yarl/_url.py", line 216, in build
    raise ValueError('Can\'t build URL with "port" but without "host".')
ValueError: Can't build URL with "port" but without "host".
```


### Python Version

```console
`Python 3.8.6`
```


### aiohttp Version

```console
`3.8.1`
```


### multidict Version

```console
`5.0.2`
```


### yarl Version

```console
`1.6.3`
```


### OS

OS X 10.11.6

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
