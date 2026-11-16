web.Request.clone bug
### Describe the bug

When I try to create a new `Request` object from an existing with `clone` and set new `scheme` and `host` parameters. The new request object's `url` will not change it's scheme and url.



### To Reproduce

```python
# Original request.url starts with 'http://'
request = request.clone(scheme='https', host='new_host')
logger.debug(request.url)  # This still starts with 'http://'
logger.debug(request.scheme)  # This will be 'https', so scheme has changed
```

### Expected behavior

The new `request` object shold start with 'https://'

### Logs/tracebacks

```python-traceback
logger.debug(request.url)
logger.debug(request.scheme)
```
```
2023-08-06 01:05:26,217 [DEBUG] http://ipecho.net/plain
2023-08-06 01:05:26,217 [DEBUG] https
```

### Python Version

```console
3.11
```


### aiohttp Version

```console
3.8.5
```


### multidict Version

```console
6.0.5
```


### yarl Version

```console
$ python -m pip show yarl
```


### OS

macOS

### Related component

Server

### Additional context

Workaround:
```python
# call clone twice
request = request.clone(scheme='https', host='new_host')  # 1st set scheme and new host
request = request.clone(scheme='https', host='new_host', rel_url=request.rel_url)  # This will update the url of the request
```

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- `Request.clone` accepts the keyword arguments `scheme`, `host`, and `remote`.
- When `scheme` is provided, the returned request's `.scheme` and `.url.scheme` reflect the new value.
- When `host` is provided, the returned request's `.host` and `.url.host` reflect the new value.
- When `remote` is provided, the returned request's `.remote` reflects the new value.
