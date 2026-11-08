Matching tail pattern in add_route/add_* handling not working as expected in 3.10.0
### Describe the bug

The usage of https://docs.aiohttp.org/en/stable/faq.html#how-do-i-create-a-route-that-matches-urls-with-a-given-prefix seems to yield different results in 3.10.0 than in 3.9.5 for a certain condition. I've included a gist in 'reproduce' which mostly mimics what our code handles

While our code might not be the neatest, we use this for our testsuite (hence no functional user issue) here https://github.com/plugwise/python-plugwise/blob/672335ddf766799df5a8d0ba32d7d04332b8a5a2/tests/test_init.py#L114 with the constants defined around L29

### To Reproduce

https://gist.github.com/CoMPaTech/541eb68906431933d2b3ea48e886b92b

### Expected behavior

Parsing incoming URLs (for example) `PUT /core/locations;id=c50f167537524366a5af7aa3942feb1e/thermostat;id=711861a52ed84f37a2d854afba34d9e6` While we also frown upon the url setup, it's what the physical boxes have in their firmware so beyond our ability to change.

### Logs/tracebacks

```python-traceback
See gist I nto reproduce
```


### Python Version

```console
3.12
```


### aiohttp Version

```console
3.10.0 (failing)
3.9.5 and earlier (functioning as expected)
```


### multidict Version

```console
6.0.5
```


### yarl Version

```console
1.9.4
```


### OS

Able to reproduce in several containers, ubuntu and macOS (regardless of version)

### Related component

Server

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
