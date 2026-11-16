Tarfile file-like objects cannot upload as `data` attributes.
### Describe the bug

`post` and other HTTP verbs with a `data` attribute can accept files and file-like objects.  `builtins.open()`, `zipfile.ZipFile.open()`, `io.BytesIO()` all transmit correctly, with the data loaded; however the `tarfile.TarFile.extractfile()` method, which by the python specification returns a file-like object, is treated as a file on disk, and [HIDDEN], which does not exist on the `tarfile._FileInFile` (nor does it exist in the `zipfile.ZipExtFile`, which does in fact work with `aiohttp`)

zipfile.open(): https://docs.python.org/3/library/zipfile.html#zipfile.ZipFile.open
tarfile.extractfile(): https://docs.python.org/3/library/tarfile.html#tarfile.TarFile.extractfile

The current spec asserts that `tarfile.TarFile.extractfile` returns an `io.BufferedReader`, but there is an intermediate `tarfile._FileInFile` object; zip works the same way, with an intermediate `zipfile.ZipExtFile` object.

`aiohttp` specification showing expected behavior: https://docs.aiohttp.org/en/stable/client_quickstart.html#streaming-uploads

### To Reproduce

Using a fully self-contained pytest, the following fails.
```python
import aiohttp
import io
import pytest
import tarfile

@pytest.mark.asyncio
async def test_tar_filelike():
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tf:
        tf.addfile(
            tarinfo=tarfile.TarInfo(name="payload1.txt", ),
            fileobj=io.StringIO("This is the first text files"),
        )

    buf.seek(0)
    async with aiohttp.ClientSession() as session:
        tf = tarfile.open(fileobj=buf, mode='r')
        for tinfo in tf.getmembers():
            tar_filelike = tf.extractfile(tinfo)
            async with session.post(url, data=tar_filelike, ) as res:
                print(await res.text())
```

This will work if directly invoked any other way, but the `pytest` and `pytest-asyncio` modules facilitated these tests.

### Expected behavior

The following works as expected, swapping only tarfile for zipfile, and replacing the method signatures as appropriate.
```python
import aiohttp
import io
import pytest
import tarfile

@pytest.mark.asyncio
async def test_zip_filelike():
    buf = io.BytesIO()
    with zipfile.ZipFile(file=buf, mode="w") as zf:
        with zf.open("payload1.txt", mode="w") as zip_filelike_writing:
            zip_filelike_writing.write("This is the first text file.".encode("utf-8"))

    buf.seek(0)
    async with aiohttp.ClientSession() as session:
        zf = zipfile.ZipFile(file=buf, mode='r')
        for zinfo in zf.infolist():
            zip_filelike = zf.open(zinfo)
            async with session.post(url, data=zip_filelike, ) as res:
                print(await res.text())
```

### Logs/tracebacks

```python-traceback
================================== FAILURES ===================================
______________________________ test_tar_filelike ______________________________

    @pytest.mark.asyncio
    async def test_tar_filelike():
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as tf:
            tf.addfile(
                tarinfo=tarfile.TarInfo(name="payload1.txt", ),
                fileobj=io.StringIO("This is the first text files"),
            )

        buf.seek(0)
        async with aiohttp.ClientSession() as session:
            tf = tarfile.open(fileobj=buf, mode='r')
            for tinfo in tf.getmembers():
                tar_filelike = tf.extractfile(tinfo)
>               async with session.post(url, data=tar_filelike, ) as res:

test\int\test_aiohttp.py:41:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
venv310\lib\site-packages\aiohttp\client.py:1138: in __aenter__
    self._resp = await self._coro
venv310\lib\site-packages\aiohttp\client.py:507: in _request
    req = self._request_class(
venv310\lib\site-packages\aiohttp\client_reqrep.py:313: in __init__
    self.update_body_from_data(data)
venv310\lib\site-packages\aiohttp\client_reqrep.py:519: in update_body_from_data
    size = body.size
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <aiohttp.payload.BufferedReaderPayload object at 0x000001E4A3B6D390>

    @property
    def size(self) -> Optional[int]:
        try:
>           [HIDDEN]
E           AttributeError: '_FileInFile' object has no attribute 'fileno'

venv310\lib\site-packages\aiohttp\payload.py:379: AttributeError
=========================== short test summary info ===========================
FAILED test/int/test_aiohttp.py::test_tar_filelike - AttributeError: '_FileIn...
========================= 1 failed, 1 passed in 0.87s =========================
```


### Python Version

```console
$./venv310/Scripts/python --version
Python 3.10.4
```


### aiohttp Version

```console
/venv310/Scripts/python -m pip show aiohttp
Name: aiohttp
Version: 3.8.1
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: .....\venv310\lib\site-packages
Requires: aiosignal, async-timeout, attrs, charset-normalizer, frozenlist, multidict, yarl
Required-by:
```


### multidict Version

```console
$ ./venv310/Scripts/python -m pip show multidict
Name: multidict
Version: 6.0.2
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: .....\venv310\lib\site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
$ ./venv310/Scripts/python -m pip show yarl
Name: yarl
Version: 1.7.2
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: .....\venv310\lib\site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

Windows 7 64 bit, but also demonstrated on Centos 7 64 bit.

### Related component

Client

### Additional context

This has been demonstrated to work consistently on Python 3.6 and 3.8 on Centos 7; Python 3.6, 3.7, and 3.10 on Windows 10 64 bit.  A fresh install of Python 3.10, with the latest available versions of aiohttp, pytest, and pytest-asyncio were used.

As a known-working workaround, that applies to both `zipfile` and `tarfile`, using a generator to manage the data does work.

```python
    async with aiohttp.ClientSession() as session:
        async def sender(f):
            chunk = f.read(64 * 1024)
            while chunk:
                yield chunk
                chunk = f.read(64 * 1024)

        tf = tarfile.open("./test/files/archives/files.tar", mode='r:')
        for tinfo in tf.getmembers():
            async with session.post(url, data=sender(tf.extractfile(tinfo))) as res:
                print(await res.text())
```

Why the actual/expected sections make use of an `io.Bytes()` object to create the file and hold it virtually, the behavior is exactly the same, with the same errors and traceback, with actual files on disk.

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- A file-like object returned by `tarfile.TarFile.extractfile()` must be usable as the `data` argument for an HTTP request, and its contents must be transmitted without failing during size determination.
