File multipart upload doesn't work with redirects getting 422 status code
### Describe the bug

I built a request to upload files to a local cloud. I detected that if there is a page redirection (307 Temporary Redirect) during the request, the following `aiohttp` request's body is built incorrectly, resulting in unexpected malformed requests.
For example, `FastAPI` servers by default accept URLs with and without trailing slashes, redirecting to the right path if a slash is miswritten. But I get 4xx errors after this redirect. If bytes are passed instead of a file stream or the right path is written (without the redirect), the server gets the correct file inside the request body.

### To Reproduce

`server.py` - small FastAPI server
```python3
from fastapi import FastAPI, UploadFile

app = FastAPI()

@app.api_route("/files", methods=["DELETE", "PATCH", "POST", "PUT"])
def update_file(file: UploadFile | None = None):
    # Working with the file
    return file.size if file else 0

if __name__ == "__main__":
    from uvicorn import run

    run("server:app", reload=True)
```

`aiohttp_request.py` - I added my tests as commented lines
```python3
from asyncio import run
from io import BufferedReader, BytesIO, FileIO, StringIO, TextIOWrapper
from typing import AsyncGenerator

from aiohttp import ClientSession, FormData

async def file_chunks(*args, **kwargs) -> AsyncGenerator[bytes, None]:
    import aiofiles

    async with aiofiles.open(*args, **kwargs) as file:
        while chunk := await file.read(64*1024):
            yield chunk

async def upload_file():
    filename = "server.py"

    # url = "http://localhost:8000/files"  # all good, always works
    url = "http://localhost:8000/files/"  # doesn't work after the FastAPI redirect

    with open(filename, "rb") as data:
    # with FileIO(filename) as data:
    # with BufferedReader(FileIO(filename)) as data:
    # with TextIOWrapper(BufferedReader(FileIO(filename))) as data:
    # with BytesIO(b"test") as data:  # works for both urls
    # with StringIO("test") as data:  # works for both urls
        formdata = FormData({"file": data})  # doesn't work with file streams
        # formdata = FormData({"file": data.read()})  # works, but passing bytes is deprecated
        # formdata = FormData(); formdata.add_field("file", file_chunks(filename, "rb"), filename=filename)  # doesn't work with redirects as it is a generator
        # formdata = None  # works as there is no passed data

        async with (
            ClientSession() as session,
            session.post(url, data=formdata) as resp,
        ):
            print(await resp.text())
            resp.raise_for_status()

if __name__ == "__main__":
    run(upload_file())
```

After running the request, the output is `[422 Unprocessable Entity] {"detail":[{"loc":["body","file"],"msg":"field required","type":"value_error.missing"}]}` (or sometimes `[400 Bad Request] Invalid HTTP request received.`)

I even made a try to write an alternative `aiohttp` web server implementation, but it still leads to errors, though they are different:
<details>
<summary>

`alternative_server.py`
</summary>
<p>

```python3
from aiohttp import web

routes = web.RouteTableDef()

@routes.route("*", "/files")
async def update_file(request):
    data = await request.post()
    print(data)
    file_field = data.get("file")
    # Working with the file
    size = len(file_field.file.read()) if file_field else 0
    return web.Response(text=str(size))

app = web.Application(middlewares=[web.normalize_path_middleware(remove_slash=True, append_slash=False)])
app.add_routes(routes)

if __name__ == "__main__":
    web.run_app(app, port=8000)
```
</p>
</details>

### Expected behavior

Behaviour is expected to be the same as without redirects. The status code `[200 OK]` is expected when the passed file is sent to the server, and its size is printed.

### Logs/tracebacks

```python-traceback
Server output:
INFO:     127.0.0.1:65045 - "POST /files/ HTTP/1.1" 307 Temporary Redirect
WARNING:  127.0.0.1:65046 - "POST /files HTTP/1.1" 400 Bad Request

Client output:
Invalid HTTP request received.
Traceback (most recent call last):
  File "C:\Users\Mike\Desktop\aiohttp_request.py", line 30, in <module>
    run(upload_file())
  File "C:\Program Files\WindowsApps\PythonSoftwareFoundation.Python.3.10_3.10.3056.0_x64__qbz5n2kfra8p0\lib\asyncio\runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "C:\Program Files\WindowsApps\PythonSoftwareFoundation.Python.3.10_3.10.3056.0_x64__qbz5n2kfra8p0\lib\asyncio\base_events.py", line 649, in run_until_complete
    return future.result()
  File "C:\Users\Mike\Desktop\aiohttp_request.py", line 26, in upload_file
    resp.raise_for_status()
  File "C:\Users\Mike\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.10_qbz5n2kfra8p0\LocalCache\local-packages\Python310\site-packages\aiohttp\client_reqrep.py", line 625, in raise_for_status
    raise ClientResponseError(
aiohttp.client_exceptions.ClientResponseError: 400, message='Bad Request', url='http://localhost:8001/files'
```

### Python Version

```console
$ python --version
Python 3.10.11
```

### aiohttp Version

```console
$ python -m pip show aiohttp
Version: 3.12.7
```

### multidict Version

```console
$ python -m pip show multidict
Version: 6.0.5
```

### propcache Version

```console
$ python -m pip show propcache
Version: 0.3.2
```

### yarl Version

```console
$ python -m pip show yarl
Version: 1.20.1
```

### OS

Microsoft Windows 11 Pro (10.0.26100)

### Related component

Client

### Additional context

```console
$ python -m pip show fastapi
Version: 0.115.12
```

As I can guess from my own tests, the problem somehow lies within `aiohttp.payload.IOBasePayload:write_with_length` method, as there are no problems with other payloads for binary data.

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct
