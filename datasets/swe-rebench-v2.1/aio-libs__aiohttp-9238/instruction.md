Weak Etag can not trigger negotiation caching
### Describe the bug

![image](https://github.com/aio-libs/aiohttp/assets/62173522/d1cb7997-1f18-490b-a440-6338e06406c1)
[HIDDEN] Is there something wrong with this implementation?

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

- When a weak `If-None-Match` ETag matches the current ETag of a resource served by `web.FileResponse`, treat it as a cache match and return a not-modified response (HTTP 304) rather than the resource as modified.
