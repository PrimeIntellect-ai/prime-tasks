AsyncResolver does not use the passed `loop` argument on 3.11 and 3.12 branches due to bad cherry-pick merge
### Describe the bug

There seems to be a backport issue in the `3.11` and `3.12` branches. The `loop` argument is not passed to `aiodns.DNSResolver` despite this being the case on the `master` branch, leading to unexpected bugs when it is used.

`master`:

https://github.com/aio-libs/aiohttp/blob/master/aiohttp/resolver.py#L87-L91

`3.11`:

https://github.com/aio-libs/aiohttp/blob/3.11/aiohttp/resolver.py#L87-L96

`3.12`:

https://github.com/aio-libs/aiohttp/blob/3.12/aiohttp/resolver.py#L87-L96

The root causes is cherry-pick commit 17af04701211874e46b14636893054ca748bb451, where the `AsyncResolver.__init__` changes were incorrectly merged from d26f16ce02be6b20bcd1087416878cb878d6fbc4, missing that `loop` had been removed as an explicit argument.

### To Reproduce

N/A

### Expected behavior

Code matches what is on `master`, using the passed-in `loop`.

### Logs/tracebacks

```python-traceback
N/A
```

### Python Version

```console
N/A
```

### aiohttp Version

```console
3.11/3.12
```

### multidict Version

```console
N/A
```

### propcache Version

```console
N/A
```

### yarl Version

```console
N/A
```

### OS

N/A

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct
