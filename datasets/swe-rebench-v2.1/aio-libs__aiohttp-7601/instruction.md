aiohttp raises SSLError when requesting URLs with FQDN
## Long story short

It seems that aiohttp doesn't work properly when requesting URLs with Fully Qualified Domain Name. This was fixed in urllib3, see https://github.com/urllib3/urllib3/pull/1255 It should probably by fixed also in aiohttp. May be related to https://github.com/aio-libs/aiohttp/issues/3171

## Expected behaviour

aiohttp works when requesting URLs with FQDN

## Actual behaviour

aiohttp raises SSL error:

```python-traceback
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/pavel/.pyenv/versions/3.7.1/lib/python3.7/asyncio/base_events.py", line 573, in run_until_complete
    return future.result()
  File "<stdin>", line 3, in main
  File "<stdin>", line 2, in fetch
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/client.py", line 1005, in __aenter__
    self._resp = await self._coro
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/client.py", line 476, in _request
    timeout=real_timeout
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/connector.py", line 522, in connect
    proto = await self._create_connection(req, traces, timeout)
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/connector.py", line 854, in _create_connection
    req, traces, timeout)
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/connector.py", line 992, in _create_direct_connection
    raise last_exc
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/connector.py", line 974, in _create_direct_connection
    req=req, client_error=client_error)
  File "/home/pavel/Projects/_lab/aiohttp/lib/python3.7/site-packages/aiohttp/connector.py", line 927, in _wrap_create_connection
    req.connection_key, exc) from exc
aiohttp.client_exceptions.ClientConnectorCertificateError: Cannot connect to host github.com.:443 ssl:True [SSLCertVerificationError: (1, "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: Hostname mismatch, certificate is not valid for 'github.com.'. (_ssl.c:1051)")]
```

## Steps to reproduce

Run the following code:

```python
import aiohttp
import asyncio


async def fetch(session, url):
    async with session.get(url) as response:
        return await response.text()

async def main():
    async with aiohttp.ClientSession() as session:
        html = await fetch(session, 'https://github.com.')
        print(html)


loop = asyncio.get_event_loop()
loop.run_until_complete(main())
```

## Your environment

Python 3.7.1
Ubuntu 18.04

pip freeze

```console
aiohttp==3.5.4
async-timeout==3.0.1
attrs==19.1.0
chardet==3.0.4
idna==2.8
multidict==4.5.2
yarl==1.3.0
```
