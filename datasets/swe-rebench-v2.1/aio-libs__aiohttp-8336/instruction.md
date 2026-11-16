Using MultipartWriter.append_json breaks in 3.9.4 with AssertionError "assert CONTENT_DISPOSITION in payload.headers"
### Describe the bug

After upgrading to 3.9.4 the following example code that used to work in 3.9.3 starts failing. I think the issue was introduced in https://github.com/aio-libs/aiohttp/commit/7d0be3fee540a3d4161ac7dc76422f1f5ea60104

### To Reproduce

```python
import aiohttp
import asyncio


async def main():
    async with aiohttp.ClientSession() as session:
        mpwriter = aiohttp.MultipartWriter('form-data')
        mpwriter.append_json({'a': 1})
        response = await session.post('https://httpbingo.org/post', data=mpwriter)
        print(await response.text())


asyncio.run(main())
```

### Expected behavior

This should print a text response, but instead it fails with an AssertionError


### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "/Users/nico/test.py", line 13, in <module>
    asyncio.run(main())
  File "/opt/homebrew/Cellar/python@3.9/3.9.18_1/Frameworks/Python.framework/Versions/3.9/lib/python3.9/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "/opt/homebrew/Cellar/python@3.9/3.9.18_1/Frameworks/Python.framework/Versions/3.9/lib/python3.9/asyncio/base_events.py", line 647, in run_until_complete
    return future.result()
  File "/Users/nico/test.py", line 8, in main
    mpwriter.append_json({'a': 1})
  File "/Users/nico/virtualenvs/gaevenv3.9/lib/python3.9/site-packages/aiohttp/multipart.py", line 887, in append_json
    return self.append_payload(JsonPayload(obj, headers=headers))
  File "/Users/nico/virtualenvs/gaevenv3.9/lib/python3.9/site-packages/aiohttp/multipart.py", line 851, in append_payload
    assert CONTENT_DISPOSITION in payload.headers
AssertionError
```
```


### Python Version

```console
Python 3.9.18
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.9.4
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /Users/nico/virtualenvs/gaevenv3.9/lib/python3.9/site-packages
Requires: aiosignal, async-timeout, attrs, frozenlist, multidict, yarl
Required-by: gcloud-aio-auth
```


### multidict Version

```console
Name: multidict
Version: 5.2.0
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /Users/nico/virtualenvs/gaevenv3.9/lib/python3.9/site-packages
Requires:
Required-by: aiohttp, sanic, yarl
```


### yarl Version

```console
Name: yarl
Version: 1.9.2
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: /Users/nico/virtualenvs/gaevenv3.9/lib/python3.9/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

macOS 14.1.1

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- For a `MultipartWriter('form-data')`, an appended part without an existing Content-Disposition must receive a default form-data name based on its zero-based position: the first part must include `name="section-0"`, and an unnamed third part must include `name="section-2"`. An explicitly set Content-Disposition must be preserved.
