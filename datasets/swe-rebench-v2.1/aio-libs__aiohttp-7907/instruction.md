Response connection is None on 3.9.0
### Describe the bug

Sorry for the not easily reproducible bug, but since 3.9.0 connection upgrading doesn't work


### To Reproduce

I experienced the bug using aiodocker exec, so forgive me for indirect reproduce of the bug:
* get a running docker container in aiodocker
* `exec_ = await container.exec(command)` (the command doesn't matter, can be ls)
* `async with exec_.start(detach=False) as stream:`
* the above line will fail

### Expected behavior

I used aiodocker version 0.21.0, when using aiohttp version 3.8.6 it works well (but uninstallable for python3.12), on version 3.9.0 it fails with  Status code: 101 (https://github.com/aio-libs/aiodocker/issues/832)

### Logs/tracebacks

```python-traceback
Unfortunately, I only got aiodocker logs:

aiodocker.exceptions.DockerError: DockerError(500, "Cannot upgrade connection to vendored tcp protocol, the docker server has closed underlying socket. Status code: 101. Headers: <CIMultiDictProxy('Content-Type': 'application/vnd.docker.multiplexed-stream', 'Connection': 'Upgrade', 'Upgrade': 'tcp', 'Api-Version': '1.43', 'Docker-Experimental': 'false', 'Ostype': 'linux', 'Server': 'Docker/24.0.7 (linux)')>.")
```
```


### Python Version

```console
$ python --version
Tested on 3.12 and 3.11
```


### aiohttp Version

```console
$ python -m pip show aiohttp
works on 3.8.6, fails on 3.9.0
```


### multidict Version

```console
$ python -m pip show multidict
6.0.4
```


### yarl Version

```console
$ python -m pip show yarl
1.9.3
```


### OS

Ubuntu

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
