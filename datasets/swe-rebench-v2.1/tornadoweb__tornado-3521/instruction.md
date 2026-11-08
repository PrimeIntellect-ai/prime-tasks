500 error if non-RFC Host is being passed in headers.
With 6.5.1 (and 6.5) I am getting 500 error if I add `Host: http//1.1.1.1:80` or similar non-RFC values.

```
2025-06-11 23:12:48,612 - tornado.application - ERROR - Uncaught exception
Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/tornado/http1connection.py", line 222, in _read_message
    header_recv_future = delegate.headers_received(start_line, headers)
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/tornado/routing.py", line 255, in headers_received
    request = httputil.HTTPServerRequest(
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/tornado/httputil.py", line 506, in __init__
    raise HTTPInputError("Invalid Host header: %r" % self.host)
tornado.httputil.HTTPInputError: Invalid Host header: 'http//1.1.1.1:80'
2025-06-11 23:12:48,614 - tornado.application - ERROR - Uncaught exception
Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/tornado/http1connection.py", line 222, in _read_message
    header_recv_future = delegate.headers_received(start_line, headers)
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/tornado/routing.py", line 255, in headers_received
    request = httputil.HTTPServerRequest(
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/tornado/httputil.py", line 506, in __init__
    raise HTTPInputError("Invalid Host header: %r" % self.host)
tornado.httputil.HTTPInputError: Invalid Host header: 'http//1.1.1.1:80'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/tornado/http1connection.py", line 221, in _read_message
    with _ExceptionLoggingContext(app_log):
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/tornado/http1connection.py", line 70, in __exit__
    raise _QuietException
tornado.http1connection._QuietException

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/tornado/http1connection.py", line 302, in _read_message
    delegate.on_connection_close()
  File "/usr/local/lib/python3.12/site-packages/tornado/routing.py", line 282, in on_connection_close
    assert self.delegate is not None
           ^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError
```
To reproduce:
`Dockerfile`
```
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir tornado==6.5.1 requests
COPY . .
EXPOSE 8888
CMD ["python", "server.py"]
```
`server.py`
```
#!/usr/bin/env python3

import asyncio
import tornado.web


class MainHandler(tornado.web.RequestHandler):

    def get(self):
        self.write({"message": "Hello from Tornado 6.5.1", "status": "running"})


def make_app():
    return tornado.web.Application([
        (r"/", MainHandler),
    ], debug=True)


async def main():
    app = make_app()
    app.listen(8888)

    print("Tornado server started on http://0.0.0.0:8888")
    print("Tornado version: 6.5.1")

    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
```
`client.py`
```
#!/usr/bin/env python3

import requests


def main() -> None:
    session = requests.Session()
    session.headers.update({"Host": "http//1.1.1.1:80"})

    try:
        response = session.get("http://localhost:8888/")
        print(f"Status: {response.status_code}")
        print(f"Response: {response.json()}")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        session.close()


if __name__ == "__main__":
    main()
```
To run:
```
podman build -t tornado-bug . && podman run -it --rm -p 8888:8888 tornado-bug
```
and from another terminal: `python client.py`

Also I think this line can be removed 😄
https://github.com/tornadoweb/tornado/blob/bb07ce9d1f0e9529b6fe9c2cebe78cfb238b4a0c/tornado/httputil.py#L505

### Additional contract requirements

- A request with an invalid Host header must receive a 400 client-error response rather than a 500 server error.
- If invalid Host parsing fails before request routing is established, connection cleanup must not raise an assertion.
- For a request with an invalid Host header, log an INFO-level message through `gen_log` matching `.*Malformed HTTP message.*Invalid Host header`.
