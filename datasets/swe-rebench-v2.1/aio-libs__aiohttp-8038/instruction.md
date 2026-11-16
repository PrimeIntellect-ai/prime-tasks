Client attempts to reuse a closed connection if "Connection: keep-alive" header was received
### Describe the bug

When making requests through a ClientSession, the session will try to reuse connections, where the "Connection: keep-alive" http header was last sent, even when the connection was closed on a lower layer.

Let's say we make a request to server.com. In the response, server.com will include (misleadingly) the header "Connection: keep-alive", but will close the connection, e.g. by closing the socket. When we try to make a second request to server.com, `ClientSession` (or the underlying connector) will  reuse this connection, even though it is closed, and the request will thus fail.

As far as I'm aware, it is not a violation of protocol to send the "Connection: keep-alive" header and then close the connection, even though it is strange behavior. The `requests` library can deal with this without any problems and I wonder if this type of behavior could cause other issues as well.

### To Reproduce

1. Run a simple http server implementation, that responds to all requests with a simple "test" response and a "Connection: keep-alive" header, but then closes the connection (after each request):
```python
"""
Simple http server that sends 'Connection: keep-alive' headers,
but closes the connection after every request
"""

import socket
import select


HOSTNAME = "localhost"
PORT = 8080


def accept_connection(server_socket: socket.socket):
    """Wait for connection, then return the client_socket"""
    select.select((server_socket,), (), (), 2)
    return server_socket.accept()


def handle_client(client_socket: socket.socket):
    """Send simple response with 'Connection: keep-alive' and close connection"""
    read_ready = select.select((client_socket,), (), ())[0]
    if not read_ready:
        raise RuntimeError("Not read_ready")
    client_socket.recv(1024)
    connection_header = "Connection: keep-alive\r\n"
    content = "test"
    content_len = f"Content-Length: {len(content)}\r\n"
    client_socket.send(
        f"HTTP/1.1 200 OK\r\n{connection_header}{content_len}\r\n{content}".encode()
    )
    client_socket.close()


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind((HOSTNAME, PORT))

    s.listen(5)
    print(f"Listening on {HOSTNAME}:{PORT}")

    while True:
        client_socket, address = accept_connection(s)
        print(f"New connection from {address}")
        handle_client(client_socket)


if __name__ == "__main__":
    main()
```

2. Call the server twice in a row with one client session:
```python
"""Call the server twice in a row"""

import aiohttp
import asyncio


async def main():
    session = aiohttp.ClientSession()
    print("making first call...")
    res = await session.get("http://localhost:8080")
    print("first call successful")
    print("headers:", res.headers)
    print("content:", await res.text())
    print("-"*20)
    print("making second call...")
    res = await session.get("http://localhost:8080")
    print("second call successful")
    print("headers:", res.headers)
    print("content:", await res.text())
    print("-"*20)

    await session.close()

if __name__ == "__main__":
    asyncio.run(main())
```

Client output:
```
making first call...
first call successful
headers: <CIMultiDictProxy('Connection': 'keep-alive', 'Content-Length': '4')>
content: test
--------------------
making second call...
Traceback (most recent call last):
  File "test_aiohttp_keep_alive.py", line 44, in <module>
    asyncio.run(main())
  File "/usr/lib/python3.9/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "/usr/lib/python3.9/asyncio/base_events.py", line 642, in run_until_complete
    return future.result()
  File "test_aiohttp_keep_alive.py", line 18, in main
    res = await session.get("http://localhost:8080")
  File "venv/lib/python3.9/site-packages/aiohttp/client.py", line 560, in _request
    await resp.start(conn)
  File "venv/lib/python3.9/site-packages/aiohttp/client_reqrep.py", line 899, in start
    message, payload = await protocol.read()  # type: ignore[union-attr]
  File "venv/lib/python3.9/site-packages/aiohttp/streams.py", line 616, in read
    await self._waiter
aiohttp.client_exceptions.ServerDisconnectedError: Server disconnected
Unclosed client session
client_session: <aiohttp.client.ClientSession object at 0x7f18495c00d0>
```


### Expected behavior

Expected output from the client script above is:
```
making first call..
second call successful
headers: {'Connection': 'keep-alive', 'Content-Length': '4'}
content: test
--------------------
making second call..
second call successful
headers: {'Connection': 'keep-alive', 'Content-Length': '4'}
content: test
--------------------
```

Which is what using the `requests` library yields.
```python
import requests

session = requests.Session()
print("making first call..")
res = session.get("http://localhost:8080")
print("first call successful")
print("headers:", res.headers)
print("content:", res.text)
print("-"*20)
print("making second call..")
res = session.get("http://localhost:8080")
print("second call successful")
print("headers:", res.headers)
print("content:", res.text)
print("-"*20)
```

### Logs/tracebacks

```python-traceback
$ sudo tcpdump tcp -i lo port 8080
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lo, link-type EN10MB (Ethernet), snapshot length 262144 bytes
12:00:23.426820 IP localhost.43634 > localhost.http-alt: Flags [S], seq 582969114, win 65495, options [mss 65495,sackOK,TS val 2734512433 ecr 0,nop,wscale 7], length 0
12:00:23.426838 IP localhost.http-alt > localhost.43634: Flags [S.], seq 3207724027, ack 582969115, win 65483, options [mss 65495,sackOK,TS val 2734512433 ecr 2734512433,nop,wscale 7], length 0
12:00:23.426851 IP localhost.43634 > localhost.http-alt: Flags [.], ack 1, win 512, options [nop,nop,TS val 2734512433 ecr 2734512433], length 0
12:00:23.427290 IP localhost.43634 > localhost.http-alt: Flags [P.], seq 1:124, ack 1, win 512, options [nop,nop,TS val 2734512433 ecr 2734512433], length 123: HTTP: GET / HTTP/1.1
12:00:23.427308 IP localhost.http-alt > localhost.43634: Flags [.], ack 124, win 511, options [nop,nop,TS val 2734512433 ecr 2734512433], length 0
12:00:23.427374 IP localhost.http-alt > localhost.43634: Flags [P.], seq 1:67, ack 124, win 512, options [nop,nop,TS val 2734512433 ecr 2734512433], length 66: HTTP: HTTP/1.1 200 OK
12:00:23.427389 IP localhost.43634 > localhost.http-alt: Flags [.], ack 67, win 512, options [nop,nop,TS val 2734512433 ecr 2734512433], length 0
12:00:23.427405 IP localhost.http-alt > localhost.43634: Flags [F.], seq 67, ack 124, win 512, options [nop,nop,TS val 2734512433 ecr 2734512433], length 0
12:00:23.428727 IP localhost.43634 > localhost.http-alt: Flags [P.], seq 124:247, ack 68, win 512, options [nop,nop,TS val 2734512435 ecr 2734512433], length 123: HTTP: GET / HTTP/1.1
12:00:23.428742 IP localhost.http-alt > localhost.43634: Flags [R], seq 3207724095, win 0, length 0
^C
10 packets captured
20 packets received by filter
0 packets dropped by kernel
```


### Python Version

```console
3.9.2
```


### aiohttp Version

```console
3.8.4
```


### multidict Version

```console
6.0.4
```


### yarl Version

```console
1.8.2
```


### OS

Debian

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
