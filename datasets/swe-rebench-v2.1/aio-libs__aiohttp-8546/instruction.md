WSS: `_pong_not_received` works (mostly) correctly but outcome is erased by `receive`'s `except EofStream:`
### Describe the bug

I'm testing a condition where a network connection is severed to see how application behaves and recovers. This is accomplished by switching the laptop into an airplane mode, disabling the WiFi interface, i.e. a hard disconnect.
I noticed that application shuts down as if receiving a normal exit signal, which isn't supposed to happen.

Tracked this down to the following:

When connection is severed with my activated `heartbeat` of 5.0, `_pong_not_received` works mostly correctly:
https://github.com/aio-libs/aiohttp/blob/e057906e52ed0ee457d4199b762e917733b51fdb/aiohttp/client_ws.py#L116-L121

However, the concurrent `receive` that returns some time thereafter with `EofStream` erases all information about the abnormal shutdown:
https://github.com/aio-libs/aiohttp/blob/e057906e52ed0ee457d4199b762e917733b51fdb/aiohttp/client_ws.py#L253-L256

[HIDDEN]

I'm working on a patch.

### To Reproduce

1. Connect to WSS endpoint and set frequent heartbeats and start receiving.
2. Sever network connection for long enough for heartbeat to timeout.
3. Observe that receive returns `WSCloseCode.OK` waaaay past the heartbeat timeout with no indication anything went wrong.

### Expected behavior

`receive`:

1) does not erase the error information from the `_pong_not_received` when `EofStream` is received.
2) terminates immediately upon `_pong_not_received` with proper termination cause.
[HIDDEN]


### Logs/tracebacks

```python-traceback
Above
```


### Python Version

```console
$ python --version
Not relevant, but `Python 3.12.4`
```


### aiohttp Version

```console
$ python -m pip show aiohttp
3.9.5
```


### multidict Version

```console
$ python -m pip show multidict
Not relevant
```


### yarl Version

```console
$ python -m pip show yarl
Not relevant
```


### OS

Fedora 40, Linux, x86_64

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

When a heartbeat pong times out, any `receive` already waiting for a message must terminate promptly with an error message that exposes the timeout/abnormal termination cause, rather than reporting a normal closure.
