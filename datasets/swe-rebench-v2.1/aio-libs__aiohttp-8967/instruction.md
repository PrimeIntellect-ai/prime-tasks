Task was destroyed but it is pending! timeout
### Describe the bug

In case of setting a ClientTimout, we are getting the following issue:

Task was destroyed but it is pending!
task: <Task pending name='Task-3' coro=<TCPConnector._resolve_host() running at /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages/aiohttp/connector.py:874> wait_for=<Future pending cb=[_chain_future.<locals>._call_check_cancel() at /labhome/python_3.10.4/lib/python3.10/asyncio/futures.py:384, Task.task_wakeup()]> cb=[TCPConnector._create_direct_connection.<locals>.drop_exception() at /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages/aiohttp/connector.py:1155]>


### To Reproduce

      client_timeout = ClientTimeout(connect=timeout)
      async with Session(headers=self.headers, timeout=client_timeout) as session:
          async with session.post(self.login_url, **params) as response:
              return response.cookies

### Expected behavior

not to see the issue

### Logs/tracebacks

```python-traceback
Task was destroyed but it is pending!
task: <Task pending name='Task-3' coro=<TCPConnector._resolve_host() running at /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages/aiohttp/connector.py:874> wait_for=<Future pending cb=[_chain_future.<locals>._call_check_cancel() at /labhome/python_3.10.4/lib/python3.10/asyncio/futures.py:384, Task.task_wakeup()]> cb=[TCPConnector._create_direct_connection.<locals>.drop_exception() at /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages/aiohttp/connector.py:1155]>
```


### Python Version

```console
$ python --version
Python 3.10.4
```


### aiohttp Version

```console
$ python -m pip show aiohttp
Name: aiohttp
Version: 3.8.3
Summary: Async http client/server framework (asyncio)
Home-page: https://github.com/aio-libs/aiohttp
Author:
Author-email:
License: Apache 2
Location: /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages
Requires: aiosignal, async-timeout, attrs, charset-normalizer, frozenlist, multidict, yarl
Required-by:
```


### multidict Version

```console
$ python -m pip show multidict
Name: multidict
Version: 6.0.2
Summary: multidict implementation
Home-page: https://github.com/aio-libs/multidict
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages
Requires:
Required-by: aiohttp, yarl
```


### yarl Version

```console
$ python -m pip show yarl
Name: yarl
Version: 1.8.1
Summary: Yet another URL library
Home-page: https://github.com/aio-libs/yarl/
Author: Andrew Svetlov
Author-email: andrew.svetlov@gmail.com
License: Apache 2
Location: /my_env/git/nlastic-connections/venv/lib/python3.10/site-packages
Requires: idna, multidict
Required-by: aiohttp
```


### OS

CentOS Linux release 7.9.2009 (Core)


### Related component

Client

### Additional context

[HIDDEN]




### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

When a client operation is cancelled by `ClientTimeout` while hostname resolution is still delayed, cleanup must not leave that resolution task pending to be destroyed or emit a “Task was destroyed but it is pending!” warning.
