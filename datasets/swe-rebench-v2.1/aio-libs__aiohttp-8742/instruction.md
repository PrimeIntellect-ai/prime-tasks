ClientResponse.json() doesn't set status code
### Describe the bug

When ClientResponse.json() raises a ContentTypeError it doesn't set the HTTP status code in that exception object. Presumably there is a status code available at that point otherwise the call to `read()` inside of `json()` would have thrown an exception? There may be other properties on the ContentTypeError class that can be set.

### To Reproduce

```
try:
    resp.json()  # throws ContentTypeError
except ContentTypeError as exc:
    print(exc.status)  # prints 0, as it was not initialized
```

### Expected behavior

The ContentTypeError is initialized like the rest of the ClientResponseError

### Logs/tracebacks

```python-traceback
n/a
```


### Python Version

```console
3.12.5
```


### aiohttp Version

```console
3.10.3
```


### multidict Version

```console
n/a
```


### yarl Version

```console
n/a
```


### OS

n/a

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
