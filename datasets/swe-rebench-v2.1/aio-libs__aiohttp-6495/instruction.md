Auth provided in URL skipped if user field is blank
### Describe the bug

Some services publish a URL like:

    https://:mypassword@ropsten.infura.io/v3/..."

You can see the user field is an empty length string. When a request is made using aiohttp, the credentials are ignored and the server responds with a 403. This differs from requests and also curl, which parse this URL as having a zero-length username and a valid password.


### To Reproduce

The request is sent without credentials

### Expected behavior

Credentials should be sent

### Logs/tracebacks

```python-traceback
N.A.
```


### Python Version

```console
$ python --version
Version: 3.7.4.post0
```


### aiohttp Version

```console
$ python -m pip show aiohttp
```


### multidict Version

```console
$ python -m pip show multidict
Version: 5.1.0
```


### yarl Version

```console
$ python -m pip show yarl
Version: 1.6.3
...
```


### OS

macOS

### Related component

Client

### Additional context

[HIDDEN]

    @classmethod
    def from_url(cls, url: URL, *, encoding: str = "latin1") -> Optional["BasicAuth"]:
        """Create BasicAuth from url."""
        if not isinstance(url, URL):
            raise TypeError("url should be yarl.URL instance")
        [HIDDEN]

The underlying cause appears to be that yarl returns `url.user=None` and `url.password=mypassword`. [HIDDEN] I will open a PR with suggested fix and test.

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- `BasicAuth.from_url` must treat a URL with a nonempty password and no username as containing credentials, returning a `BasicAuth` with an empty login and that password.
- A request made with such a URL must send the credentials using Basic authentication rather than omit them.
