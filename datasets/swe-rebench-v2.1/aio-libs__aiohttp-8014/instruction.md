FileResponse + enable_compression + .gz will compress twice
### Describe the bug

When using `aiohttp.web.FileResponse` to return a file from disk, it is possible to use compression. As I understand from source code - I could not find documentation for FileResponse. There are two possible ways:

1. calling `response.enable_compression()` will make `FileResponse` automatically compress the file
2. when I call `FileResponse('some_file')` and `some_file.gz` exists, it will use the compressed version

Both ways work as expected.

But when both is appliend at the same time:

```python
response = FileResponse('some_file')
response.enable_compression()
return response
```

and _also_ `some_file.gz` exists, the response will be compressed twice - contents of `some_file.gz` is compressed via `deflate`.

### To Reproduce

```python
async def test_file_response_gz_with_enable_compression(aiohttp_client, tmp_path):

    async def file_handler(request):
        assert request.headers['Accept-Encoding'] == 'gzip, deflate'
        (tmp_path / 'file.gz').write_bytes(gzip.compress(b'Hello, compressed!'))
        response = FileResponse(tmp_path / 'file')
        response.enable_compression()
        return response

    app = Application()
    app.router.add_get('/file', file_handler)

    test_client = await aiohttp_client(app)
    resp = await test_client.get('/file')
    assert resp.status == 200
    assert resp.headers['Content-Type'] == 'application/octet-stream'
    assert resp.headers['Content-Encoding'] == 'deflate' # This should be gzip
    assert resp.headers['Transfer-Encoding'] == 'chunked'
    data = await resp.read()

    # This is how it should work:
    # assert data == b'Hello, compressed!'

    # But currently it works this way:
    assert gzip.decompress(data) == b'Hello, compressed!'
```

When using `enable_compression()` with non-compressed `file`, or using compressed `file.gz` without `enable_compression()`, it works as expected:

```python
async def test_file_response_gz_without_enable_compression(aiohttp_client, tmp_path):

    async def file_handler(request):
        assert request.headers['Accept-Encoding'] == 'gzip, deflate'
        (tmp_path / 'file.gz').write_bytes(gzip.compress(b'Hello, compressed!'))
        response = FileResponse(tmp_path / 'file')
        return response

    app = Application()
    app.router.add_get('/file', file_handler)

    test_client = await aiohttp_client(app)
    resp = await test_client.get('/file')
    assert resp.status == 200
    assert resp.headers['Content-Type'] == 'application/octet-stream'
    assert resp.headers['Content-Encoding'] == 'gzip'
    assert 'Transfer-Encoding' not in resp.headers
    data = await resp.read()

    # This is how it should work:
    assert data == b'Hello, compressed!'


async def test_file_response_no_gz_with_enable_compression(aiohttp_client, tmp_path):

    async def file_handler(request):
        assert request.headers['Accept-Encoding'] == 'gzip, deflate'
        (tmp_path / 'file').write_bytes(b'Hello, world!')
        assert not (tmp_path / 'file.gz').exists()
        response = FileResponse(tmp_path / 'file')
        response.enable_compression()
        return response

    app = Application()
    app.router.add_get('/file', file_handler)

    test_client = await aiohttp_client(app)
    resp = await test_client.get('/file')
    assert resp.status == 200
    assert resp.headers['Content-Type'] == 'application/octet-stream'
    assert resp.headers['Content-Encoding'] == 'deflate'
    assert resp.headers['Transfer-Encoding'] == 'chunked'
    data = await resp.read()

    # This is how it should work:
    assert data == b'Hello, world!'

```


### Expected behavior

When both `response.enable_compression()` was called and `some_file.gz` is present, I expect `some_file.gz` is returned as it is, without additional compression, with appropriate headers. Which is how it works if `response.enable_compression()` was not called.

### Logs/tracebacks

```python-traceback
No logs.
```


### Python Version

```console
$ ./venv/bin/python3 --version
Python 3.12.0
```


### aiohttp Version

```console
$ ./venv/bin/python3 -m pip show aiohttp
Name: aiohttp
Version: 3.9.1
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /home/messa/code/misc/2024/20240108_aiohttp_tests/venv/lib/python3.12/site-packages
Requires: aiosignal, attrs, frozenlist, multidict, yarl
Required-by: pytest-aiohttp
```


### multidict Version

```console
$ ./venv/bin/python3 -m pip show multidict
Name: multidict
Version: 6.0.4
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /home/messa/code/misc/2024/20240108_aiohttp_tests/venv/lib/python3.12/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
$ ./venv/bin/python3 -m pip show yarl
Name: yarl
Version: 1.9.4
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache-2.0
Location: /home/messa/code/misc/2024/20240108_aiohttp_tests/venv/lib/python3.12/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

$ uname -a
Linux dev-messa202301 6.1.0-0.deb11.7-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.20-2~bpo11+1 (2023-04-23) x86_64 GNU/Linux
$ cat /etc/debian_version
11.8

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
