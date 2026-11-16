ClientSession timeout AttributeError
### Describe the bug

When you create a client with `client.ClientSession(timeout=500)` does not raise or warn that timeout must be implemented as `ClientTimeout` but fails when sending a get request
Code lets you implement a client as `client.ClientSession(timeout='bad_arg')`

### To Reproduce

1. Implement a client with timeout of type `int` or `float` and send a get request

```
import asyncio
import aiohttp

async def main():
    # No issues creating a client session
    aiohttp_client = aiohttp.ClientSession(timeout=100)

    try:
        # Fails sending GET request
        await aiohttp_client.get("https://example.com", )
    finally:
        # Close client session
        await aiohttp_client.close()

asyncio.run(main())
```

2. Implement a session with  timeout as `str` type
```
aiohttp_client = aiohttp.ClientSession(timeout='bad_arg')
```

### Expected behavior

A `ValueError` has to be raised when using something other than `ClientTimeout` or `None`.

### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "/Users/voltaic/workspace/parsing_excersizes/async_requests/main.py", line 15, in <module>
    asyncio.run(main())
  File "/opt/homebrew/Cellar/python@3.12/3.12.1/Frameworks/Python.framework/Versions/3.12/lib/python3.12/asyncio/runners.py", line 194, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.12/3.12.1/Frameworks/Python.framework/Versions/3.12/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.12/3.12.1/Frameworks/Python.framework/Versions/3.12/lib/python3.12/asyncio/base_events.py", line 684, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "/Users/voltaic/workspace/parsing_excersizes/async_requests/main.py", line 10, in main
    await aiohttp_client.get("https://example.com", )
  File "/Users/voltaic/Library/Application Support/hatch/env/virtual/async-requests/3bENKOFX/async-requests/lib/python3.12/site-packages/aiohttp/client.py", line 470, in _request
    self._loop, real_timeout.total, ceil_threshold=real_timeout.ceil_threshold
                ^^^^^^^^^^^^^^^^^^
AttributeError: 'int' object has no attribute 'total'
```


### Python Version

```console
Python 3.12.1
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.9.1
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /Users/voltaic/Library/Application Support/hatch/env/virtual/async-requests/3bENKOFX/async-requests/lib/python3.12/site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by:
```


### multidict Version

```console
Name: multidict
Version: 6.0.4
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /Users/voltaic/Library/Application Support/hatch/env/virtual/async-requests/3bENKOFX/async-requests/lib/python3.12/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
Name: yarl
Version: 1.9.4
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: /Users/voltaic/Library/Application Support/hatch/env/virtual/async-requests/3bENKOFX/async-requests/lib/python3.12/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

macOS, Linux

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
