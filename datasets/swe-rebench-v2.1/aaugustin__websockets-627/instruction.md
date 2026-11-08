Unexpected ConnectionClosed in keepalive ping task
Using websockets 7.0 on Python 3.7, this can occur semi-frequently:
```
Unexpected exception in keepalive ping task
Traceback (most recent call last):
  File "C:\Program Files\Python37\lib\site-packages\websockets\protocol.py", line 989, in keepalive_ping
	ping_waiter, self.ping_timeout, loop=self.loop
  File "C:\Program Files\Python37\lib\asyncio\tasks.py", line 416, in wait_for
	return fut.result()
websockets.exceptions.ConnectionClosed: WebSocket connection is closed: code = 1006 (connection closed abnormally [internal]), no reason
```
This sometimes is followed by:
```
Error in data transfer
Traceback (most recent call last):
  File "C:\Program Files\Python37\lib\site-packages\websockets\protocol.py", line 674, in transfer_data
	message = yield from self.read_message()
  File "C:\Program Files\Python37\lib\site-packages\websockets\protocol.py", line 742, in read_message
	frame = yield from self.read_data_frame(max_size=self.max_size)
  File "C:\Program Files\Python37\lib\site-packages\websockets\protocol.py", line 846, in read_data_frame
	pong_waiter.set_result(None)
asyncio.base_futures.InvalidStateError: invalid state
```
The first error seems to contradict the documentation in `keepalive_ping`:
https://github.com/aaugustin/websockets/blob/8fc78fee48d52bb3c690e925bad0825613319296/src/websockets/protocol.py#L967 I believe this is because pending keepalive pings are now aborted with `ConnectionClosed` in 7.0 (#467).

I think the latter error is because the ping is [HIDDEN] where `ConnectionClosed` is raised:
[HIDDEN] raising [an error](https://docs.python.org/3/library/asyncio-exceptions.html#asyncio.InvalidStateError) [HIDDEN].

### Additional contract requirements

- If a pong arrives after connection loss has already completed its ping waiter, processing that pong must not cause the data-transfer task to fail with `InvalidStateError`.
