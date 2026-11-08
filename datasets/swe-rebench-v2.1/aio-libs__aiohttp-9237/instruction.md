Weak Etag can not trigger negotiation caching
### Describe the bug

![image](https://github.com/aio-libs/aiohttp/assets/62173522/d1cb7997-1f18-490b-a440-6338e06406c1)
If the above code is a weak Etag, the judgment logic in the any function will not be executed, and finally return False, resulting in the failure of the negotiation cache. Why can't the weak Etag judge that etag.value==etag_value? Is there something wrong with this implementation?

### To Reproduce

Return the resource file through web.FileResponse, and convert the returned Etag into a weak Etag, that is, add the W/ prefix

### Expected behavior

Weak Etag can also trigger negotiation caching

### Logs/tracebacks

```python-traceback
none
```


### Python Version

```console
Python 3.10.11
```


### aiohttp Version

```console
3.9.1
```


### multidict Version

```console
6.0.4
```


### yarl Version

```console
1.9.4
```


### OS

Linux

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [ ] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- For a file served by `web.FileResponse`, a conditional GET whose `If-None-Match` header carries a weak validator (`W/"..."`) with the same opaque value as the file's current `ETag` must receive `304 Not Modified`, with the same `ETag` header and an empty body.
- A weak validator whose opaque value differs from the file's current `ETag` must not produce `304 Not Modified`; the full `200 OK` response with the file body is returned.
