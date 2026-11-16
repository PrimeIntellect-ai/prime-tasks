Request is not cancelled on timeout, its response is returned for the next request
### Describe the bug

I see this strange behaviour in version 3.9.0 when I iterate to retry timed out request. It started with version 3.9.0b1.
Version 3.9.0b0 works as expected.

The probelm is when the initial request times out it should get cancelled, and indeed that iteration catches TimeoutError. The next iteration, which retries the request with new parameters somehow returns the response of the inittial cancelled request...

Please see the minimal reproducing example.

### To Reproduce

```python
import asyncio

import aiohttp


async def minimum_error():
    url = "http://httpbin.org/delay/10"
    timeout = aiohttp.ClientTimeout(total=7)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        for i in range(2):
            print(f"iteration {i} start")
            try:
                async with session.get(url, params={"iteration": i}) as resp:
                    print("ok", resp.status)
                    print(await resp.text())
            except TimeoutError:
                print("aiohttp timeout")
                await asyncio.sleep(1)
                continue
            except asyncio.CancelledError:
                print("aiohttp cancelled???")
                raise
            finally:
                print(f"iteration {i} done")


asyncio.run(minimum_error())
```

### Expected behavior

Correct results with 3.9.0b0
```
iteration 0 start
aiohttp timeout
iteration 0 done
iteration 1 start
aiohttp timeout
iteration 1 done
```

### Logs/tracebacks

```python-traceback
Actual results with 3.9.0:

iteration 0 start
aiohttp timeout
iteration 0 done
iteration 1 start
ok 200
{
  "args": {
    "iteration": "0"
  },
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Accept-Encoding": "gzip, deflate, br",
    "Host": "httpbin.org",
    "User-Agent": "Python/3.12 aiohttp/3.9.0"
  },
  "url": "http://httpbin.org/delay/10?iteration=0"
}

iteration 1 done
```


### Python Version

```console
$ python --version
Python 3.12.0
```


### aiohttp Version

```console
$ python -m pip show aiohttp
Name: aiohttp
Version: 3.9.0
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /home/andy/.local/lib/python3.12/site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by: web3
```


### multidict Version

```console
$ python -m pip show multidict
Name: multidict
Version: 6.0.4
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /home/andy/.local/lib/python3.12/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
$ python -m pip show yarl
Name: yarl
Version: 1.9.3
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: /home/andy/.local/lib/python3.12/site-packages
Requires: idna, multidict
Required-by: aiohttp, gql
```


### OS

Ubuntu Linux

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
