client: unexpected timeouts with chunked uploads when setting sock_read timeout
### Describe the bug

Uploading large files using `put`/`post` with chunked encoding AND setting `sock_read` timeout results in an unexpected timeout error.

Traceback is provided below.

### To Reproduce

Server code (aiohttp):

```python
import asyncio
import aiohttp

PORT = 8472
HOST = "localhost"


async def handler(request: aiohttp.web.Request) -> aiohttp.web.StreamResponse:
    loop = asyncio.get_running_loop()
    print(f"[{loop.time()}] got request")

    response = aiohttp.web.StreamResponse()
    response.enable_chunked_encoding()
    writer = await response.prepare(request)

    read_data = 0
    print(f"[{loop.time()}] started streaming body")

    async for data, _ in request.content.iter_chunks():
        read_data += len(data)
        print(f"[{loop.time()}] {read_data=}", end="\r")
        await asyncio.sleep(1e-4)    # NOTE: tweaking this and/or the above print, along with `sock_read` in the client might yield different results (successful upload instead of timeout)

    await writer.write_eof()
    print(f"\n[{loop.time()}] finished")

    print(f"[{loop.time()}] finished reading body {read_data=}")
    return response


async def main():
    """ listens and streams the body of a chunked transfer upload """
    loop = asyncio.get_event_loop()

    server = aiohttp.web.Server(handler)
    await loop.create_server(server, HOST, PORT)
    print(f"Listening on http://{HOST}:{PORT}")

    try:
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        print("Shutting down")
        await server.shutdown(10)


if __name__ == "__main__":
    asyncio.run(main())
```

Client code:

```python
import asyncio
import aiohttp

PORT = 8472
HOST = "localhost"


SOCK_READ_TIMEOUT = 5 # tweaking this and/or the sleep in the server implementation might yield different results


async def gen_chunks(
    payload_size: int,
    chunk_size: int = 0x1000,  # 4k
):
    processed = 0
    while processed < payload_size:
        if (processed + chunk_size) > payload_size:
            # final chunk
            chunk_size = payload_size - processed
        yield b"Z" * chunk_size
        processed += chunk_size


async def main(payload_size: int, method: str = "put", **kwargs):
    url = f"http://{HOST}:{PORT}"
    remote_path = "file"

    timeout = aiohttp.ClientTimeout(
        total=None,
        connect=0,
        sock_connect=0,
        sock_read=SOCK_READ_TIMEOUT,
    )
    async with aiohttp.ClientSession(timeout=timeout) as session:
        meth = getattr(session, method)
        async with meth(
            f"{url}/{remote_path}",
            data=gen_chunks(payload_size),
            **kwargs,
        ) as resp:
            resp.raise_for_status()
            print(f"{resp.status=}, {await resp.read()}")


if __name__ == "__main__":
    payload_1gb = 1024 * 0x100000

    asyncio.run(main(payload_1gb))
```


### Expected behavior

Upload should succeed with no timeout.

In particular, the `ServerTimeoutError` exception is raised because we're waiting to read from the protocol while `StreamWriter` is still sending data.

[HIDDEN]

Since nothing will be read from the `ResponseHandler` until all of the chunks are sent to the server, any upload that takes longer than `sock_read` s to upload will fail with a timeout.

[HIDDEN]


### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "aiohttp/timeouts_investigation.py", line 291, in <module>
    asyncio.run(main_client(payload_size))
  File "/usr/lib/python3.10/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "/usr/lib/python3.10/asyncio/base_events.py", line 649, in run_until_complete
    return future.result()
  File "aiohttp/timeouts_investigation.py", line 140, in main_client
    async with meth(
  File "aiohttp/aiohttp/client.py", line 1141, in __aenter__
    self._resp = await self._coro
  File "aiohttp/aiohttp/client.py", line 560, in _request
    await resp.start(conn)
  File "aiohttp/aiohttp/client_reqrep.py", line 899, in start
    message, payload = await protocol.read()  # type: ignore[union-attr]
  File "aiohttp/aiohttp/streams.py", line 616, in read
    await self._waiter
aiohttp.client_exceptions.ServerTimeoutError: Timeout on reading data from socket
```


### Python Version

```console
3.10.8
```


### aiohttp Version

```console
3.8.3
```


### multidict Version

```console
5.2.0
```


### yarl Version

```console
1.8.1
```


### OS

Linux

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
