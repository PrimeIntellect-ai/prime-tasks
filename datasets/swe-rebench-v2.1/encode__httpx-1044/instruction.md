0.13: some `httpcore` exceptions are missing from top level package
### Checklist
- [x] The bug is reproducible against the latest release and/or `master`.
- [x] There are no similar issues or pull requests to fix it yet.

### Describe the bug
I believe that `HTTPError` is expected to be the base exception for all exceptions that httpx may raise? Since 0.13 this is no longer true and comments in [`_exceptions.py`](https://github.com/encode/httpx/blob/master/httpx/_exceptions.py#L11) indicate this is a bug. In real world use I have at least one bit of code that has failed due to this. I could see an argument for trying to catch a more specific error, but I think this case `HTTPError` was really nice to use.

Even if users should be using more specific exceptions having a single base exception is an incredibly useful feature for any library and it'd be great if we could ensure this behavior is set for the upcoming 1.0 release.

### To reproduce
The following code assumes localhost does not have any webserver running on port 80. Running on httpx 0.12 it correctly catches the `HTTPError`, running on 0.13 it does not catch the exception (httpcore.ConnectError, which doesn't appear to be properly exported in [`\_\_init\_\_.py](https://github.com/encode/httpx/blob/master/httpx/__init__.py), though it is aliased in `_exceptions.py`).
```python
import httpx
try:
    httpx.get('http://localhost')
except httpx.HTTPError:
    print('There was an httpx error')
```

### Expected behavior
If `HTTPError` is the base exception for httpx I'd expect catching `HTTPError` to actually catch all errors httpx may raise.

### Actual behavior
Instead of catching `HTTPError` it appears that httpcore errors bubble up. This breaks exception handling that expects `HTTPError` to be the base exception.

### Environment
- OS: macOS 10.15.5
- Python version: 3.8.3
- HTTPX version: 0.13
- Async environment: asyncio
- HTTP proxy: No
- Custom certificates: No

### Additional contract requirements

- The guarantee that catching `HTTPError` catches all errors HTTPX may raise applies to both synchronous (`Client`) and asynchronous (`AsyncClient`) operations.
