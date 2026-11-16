ZLibCompressor issue leading to Websocket anomalies
### Describe the bug

After upgrading aiohttp to version 3.9.0, I encountered an intermittent error where the browser reports an 'Invalid frame header' during websocket access.
On delving deeper, I found that the websocket module in aiohttp, when compressing the data, replaced zlib.compressobj with ZLibCompressor to support max_sync_chunk_size. The specific change can be traced to this commit: https://github.com/aio-libs/aiohttp/commit/586778f19b67a26a7d7ed9cd20add9b5b4dea96c. However, ZLibCompressor was only initialized once in the WebSocketWriter and shared across multiple coroutines. However, its logic does not support usage in multiple coroutines. When different coroutines simultaneously call the websocket to send messages, the compressed results get mixed up, leading to frame inconsistencies.
[HIDDEN]

### To Reproduce

```
from aiohttp.compression_utils import ZLibCompressor
import zlib
import asyncio
import random
import string

compressobj = ZLibCompressor(
    level=zlib.Z_BEST_SPEED,
    wbits=-15,
    max_sync_chunk_size=5 * 1024,
)


def generate_random_string(length):
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for i in range(length))


async def test(compressobj):
    # test code from aiohttp.http_websocket.py: _send_frame
    # https://github.com/aio-libs/aiohttp/commit/586778f19b67a26a7d7ed9cd20add9b5b4dea96c#diff-29db742fa68fd59f39e1ca70379c4d478101a8ed9af8895c8fc7604bbf1b4b11R625
    message = generate_random_string(1232323).encode()
    message = await compressobj.compress(message)  # await cause coroutine switching
    message += compressobj.flush(zlib.Z_SYNC_FLUSH)  # data maybe from other coroutine
    return message


loop = asyncio.get_event_loop()
# parallel running 10 coroutines
tasks = [test(compressobj) for i in range(10)]
messages = loop.run_until_complete(asyncio.gather(*tasks))

for message in messages:
    decompressor = zlib.decompressobj(wbits=-15)
    message = decompressor.decompress(message) # E   zlib.error: Error -3 while decompressing data: invalid stored block lengths
```


### Expected behavior

correct compression

### Logs/tracebacks

```python-traceback
Invalid frame header
```


### Python Version

```console
Python 3.11.1
```


### aiohttp Version

```console
Name: aiohttp
Version: 3.9.0
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /Users/xiaohuanshu/PycharmProjects/bazhen/venv/lib/python3.11/site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by: aiohttp-debugtoolbar, aiohttp-devtools, aiohttp-jinja2, aiohttp-pydantic, pytest-aiohttp
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
Location: /Users/xiaohuanshu/PycharmProjects/bazhen/venv/lib/python3.11/site-packages
Requires:
Required-by: aiohttp, yarl
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
Location: /Users/xiaohuanshu/PycharmProjects/bazhen/venv/lib/python3.11/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

macOS

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- Concurrent compressed WebSocket sends must produce valid frames containing their original messages without cross-message corruption.
