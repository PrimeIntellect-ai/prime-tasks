HttpCommunicator does not raise exception from consumer
If `WebsocketCommunicator` encounters an error, it shows the exception raised by the underlying consumer. In contrast, `HttpCommunicator` just shows a `TimeoutError`, which is not useful for debugging.

Example tests:

```py
from channels.generic.http import AsyncHttpConsumer
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.testing import HttpCommunicator
from channels.testing import WebsocketCommunicator
from django.test import TestCase


class HttpConsumer(AsyncHttpConsumer):
    async def handle(self, body):
        1 / 0


class WebsocketConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        1 / 0


class ConsumerTests(TestCase):
    async def test_http(self):
        communicator = HttpCommunicator(HttpConsumer.as_asgi(), "GET", "/")
        await communicator.get_response()

    async def test_websocket(self):
        communicator = WebsocketCommunicator(WebsocketConsumer.as_asgi(), "/")
        connected, subprotocol = await communicator.connect()
```

Output:

```
$ python manage.py test
Found 2 test(s).
Creating test database for alias 'default'...
Destroying old test database for alias 'default'...
System check identified no issues (0 silenced).
<Task finished name='Task-2' coro=<HttpConsumer() done, defined at /Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/consumer.py:92> result=None>
E<Task finished name='Task-7' coro=<WebsocketConsumer() done, defined at /Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/consumer.py:92> exception=ZeroDivisionError('division by zero')>
E
======================================================================
ERROR: test_http (example.tests.ConsumerTests)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 74, in receive_output
    return await self.output_queue.get()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/asyncio/queues.py", line 159, in get
    await getter
asyncio.exceptions.CancelledError

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/sync.py", line 218, in __call__
    return call_result.result()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/concurrent/futures/_base.py", line 451, in result
    return self.__get_result()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/concurrent/futures/_base.py", line 403, in __get_result
    raise self._exception
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/sync.py", line 284, in main_wrap
    result = await self.awaitable(*args, **kwargs)
  File "/Users/chainz/tmp/channelstest/example/tests.py", line 21, in test_http
    await communicator.get_response()
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/testing/http.py", line 42, in get_response
    response_start = await self.receive_output(timeout)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 86, in receive_output
    raise e
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 73, in receive_output
    async with async_timeout(timeout):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/timeout.py", line 65, in __aexit__
    self._do_exit(exc_type)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/timeout.py", line 102, in _do_exit
    raise asyncio.TimeoutError
asyncio.exceptions.TimeoutError

======================================================================
ERROR: test_websocket (example.tests.ConsumerTests)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 74, in receive_output
    return await self.output_queue.get()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/asyncio/queues.py", line 159, in get
    await getter
asyncio.exceptions.CancelledError

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 73, in receive_output
    async with async_timeout(timeout):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/timeout.py", line 65, in __aexit__
    self._do_exit(exc_type)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/timeout.py", line 102, in _do_exit
    raise asyncio.TimeoutError
asyncio.exceptions.TimeoutError

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/sync.py", line 218, in __call__
    return call_result.result()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/concurrent/futures/_base.py", line 451, in result
    return self.__get_result()
  File "/Users/chainz/.pyenv/versions/3.10.8/lib/python3.10/concurrent/futures/_base.py", line 403, in __get_result
    raise self._exception
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/sync.py", line 284, in main_wrap
    result = await self.awaitable(*args, **kwargs)
  File "/Users/chainz/tmp/channelstest/example/tests.py", line 25, in test_websocket
    connected, subprotocol = await communicator.connect()
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/testing/websocket.py", line 36, in connect
    response = await self.receive_output(timeout)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/asgiref/testing.py", line 79, in receive_output
    self.future.result()
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/consumer.py", line 94, in app
    return await consumer(scope, receive, send)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/consumer.py", line 62, in __call__
    await await_many_dispatch([receive], self.dispatch)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/utils.py", line 50, in await_many_dispatch
    await dispatch(result)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/consumer.py", line 73, in dispatch
    await handler(message)
  File "/Users/chainz/tmp/channelstest/venv/lib/python3.10/site-packages/channels/generic/websocket.py", line 173, in websocket_connect
    await self.connect()
  File "/Users/chainz/tmp/channelstest/example/tests.py", line 15, in connect
    1 / 0
ZeroDivisionError: division by zero

----------------------------------------------------------------------
Ran 2 tests in 2.016s

FAILED (errors=2)
Destroying test database for alias 'default'...
```

Please also try and include, if you can:

(Channels 4.0.0, with Django 4.1.3, on Python 3.10.8)
