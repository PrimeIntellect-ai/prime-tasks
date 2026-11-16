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

When `clone` receives a scheme override, the cloned request's `scheme` and URL scheme reflect that value. When it receives a host override, the cloned request's `host` and URL host reflect that value. Both overrides must take effect when supplied together.
