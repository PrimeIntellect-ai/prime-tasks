3.10.0 and 4.0.0 incorrectly reject wss:// urls
### Describe the bug

In discord.py a single wss:// type url is needed to create a websocket using aiohttp to discord's api. This both allows for new and resumed connections.

```
Traceback (most recent call last):
  File "client.py", line 664, in connect
  File "asyncio\tasks.py", line 507, in wait_for
  File "gateway.py", line 374, in from_client
  File "http.py", line 550, in ws_connect
  File "client.py", line 889, in _ws_connect
  File "client.py", line 477, in _request
aiohttp.client_exceptions.NonHttpUrlClientError: wss://gateway.discord.gg/?v=10&encoding=json&compress=zlib-stream

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "__init__.py", line 49, in bot_main
  File "asyncio\runners.py", line 194, in run
  File "asyncio\runners.py", line 118, in run
  File "asyncio\base_events.py", line 721, in run_until_complete
  File "__init__.py", line 38, in run_bot
  File "client.py", line 787, in start
  File "client.py", line 723, in connect
AttributeError: 'NoneType' object has no attribute 'sequence'
Task exception was never retrieved
future: <Task finished name='discord-ext-tasks: VerificationTask.expire_verifications' coro=<Loop._loop() done, defined at __init__.py:202> exception=RuntimeError('Client has not been properly initialised. Please use the login method or asynchronous context manager before calling this method')>
Traceback (most recent call last):
  File "__init__.py", line 204, in _loop
  File "__init__.py", line 188, in _call_loop_function
  File "__init__.py", line 155, in before_task
  File "client.py", line 1149, in wait_until_ready
RuntimeError: Client has not been properly initialised. Please use the login method or asynchronous context manager before calling this method
Unclosed connector
connections: ['[(<aiohttp.client_proto.ResponseHandler object at 0x00000209B9AD7AD0>, 221376.2822786)]']
connector: <aiohttp.connector.TCPConnector object at 0x00000209B9AEABA0>
```

### To Reproduce

1. Install Discord.py & asqlite & audioop-lts
2. Install aiohttp 3.10 (branch) or 4.0.0 (default branch) from source to a manually installed cpython main build (by building installers and running them to install globally)
3. Run discord bot made in discord.py.

### Expected behavior

Everything to work, this should not have broken at all. wss links in discord api is needed through aiohttp because both ``requests`` and any other methods of connecting to discord's api is not going to work inside of a running event loop (it blocks it and is really bad to do that). As such I think it needs expanded to allow wss:// links as a special case.

### Logs/tracebacks

```python-traceback
Traceback (most recent call last):
  File "client.py", line 664, in connect
  File "asyncio\tasks.py", line 507, in wait_for
  File "gateway.py", line 374, in from_client
  File "http.py", line 550, in ws_connect
  File "client.py", line 889, in _ws_connect
  File "client.py", line 477, in _request
aiohttp.client_exceptions.NonHttpUrlClientError: wss://gateway.discord.gg/?v=10&encoding=json&compress=zlib-stream

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "__init__.py", line 49, in bot_main
  File "asyncio\runners.py", line 194, in run
  File "asyncio\runners.py", line 118, in run
  File "asyncio\base_events.py", line 721, in run_until_complete
  File "__init__.py", line 38, in run_bot
  File "client.py", line 787, in start
  File "client.py", line 723, in connect
AttributeError: 'NoneType' object has no attribute 'sequence'
Task exception was never retrieved
future: <Task finished name='discord-ext-tasks: VerificationTask.expire_verifications' coro=<Loop._loop() done, defined at __init__.py:202> exception=RuntimeError('Client has not been properly initialised. Please use the login method or asynchronous context manager before calling this method')>
Traceback (most recent call last):
  File "__init__.py", line 204, in _loop
  File "__init__.py", line 188, in _call_loop_function
  File "__init__.py", line 155, in before_task
  File "client.py", line 1149, in wait_until_ready
RuntimeError: Client has not been properly initialised. Please use the login method or asynchronous context manager before calling this method
Unclosed connector
connections: ['[(<aiohttp.client_proto.ResponseHandler object at 0x00000209B9AD7AD0>, 221376.2822786)]']
connector: <aiohttp.connector.TCPConnector object at 0x00000209B9AEABA0>
```


### Python Version

```console
$ python --version
3.14.0a0
```


### aiohttp Version

```console
$ python -m pip show aiohttp
3.10.0.dev0
```


### multidict Version

```console
$ python -m pip show multidict
6.0.5
```


### yarl Version

```console
$ python -m pip show yarl
1.9.4
```


### OS

Windows

### Related component

Server, Client

### Additional context

I also packed everything into a zip file and embedded python with the ability to load c extensions from zip file.

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
