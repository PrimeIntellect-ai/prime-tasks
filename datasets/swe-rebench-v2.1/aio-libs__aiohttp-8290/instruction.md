"Unclosed client session" when initialization fails
### Describe the bug

This is actually a wrong use case.

Some parameters will be checked after the connection is established.

So the connection cannot be closed if there are incorrect parameters.

```python
# -*- coding: utf-8 -*-
import asyncio

from aiohttp import ClientSession


async def main():
    async with ClientSession(timeout=1):
        pass


if __name__ == '__main__':
    asyncio.run(main())
```

[HIDDEN]

### To Reproduce

as above

### Expected behavior

First check that the parameters are correct and then establish the connection.

### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "D:\proj\test.py", line 13, in <module>
    asyncio.run(main())
  File "C:\Users\user\Miniconda3\Lib\asyncio\runners.py", line 190, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "C:\Users\user\Miniconda3\Lib\asyncio\runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\user\Miniconda3\Lib\asyncio\base_events.py", line 653, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "D:\proj\test.py", line 8, in main
    async with ClientSession(timeout=1):
               ^^^^^^^^^^^^^^^^^^^^^^^^
  File "D:\proj\.venv\Lib\site-packages\aiohttp\client.py", line 292, in __init__
    raise ValueError(
ValueError: timeout parameter cannot be of <class 'int'> type, please use 'timeout=ClientTimeout(...)'
Unclosed client session
client_session: <aiohttp.client.ClientSession object at 0x000001D74DC83CD0>
```


### Python Version

```console
$ python --version
Python 3.11.6
```


### aiohttp Version

```console
$ python -m pip show aiohttp
Name: aiohttp
Version: 3.9.3
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: D:\proj\.venv\Lib\site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by:
```


### multidict Version

```console
$ python -m pip show multidict
Name: multidict
Version: 6.0.5
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: D:\proj\.venv\Lib\site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
$ python -m pip show yarl
Name: yarl
Version: 1.9.4
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: D:\proj\.venv\Lib\site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

Windows 10

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- Reject an invalid timeout such as `timeout=1` with `ValueError` before connection setup begins. Failed construction must not produce an unclosed-client-session warning.
