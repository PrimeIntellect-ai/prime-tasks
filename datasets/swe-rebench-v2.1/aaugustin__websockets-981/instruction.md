Error in data transfer due to 1006
I'm writing some stress tests for a web app and I expect that no matter what clients do the server should never experience an error. However, the test occasionally fails because the below shows in the log:

```text
ERROR    websockets.protocol:protocol.py:805 Error in data transfer
Traceback (most recent call last):
  File "venv/lib/python3.9/site-packages/websockets/legacy/protocol.py", line 750, in transfer_data
    message = await self.read_message()
  File "venv/lib/python3.9/site-packages/websockets/legacy/protocol.py", line 819, in read_message
    frame = await self.read_data_frame(max_size=self.max_size)
  File "venv/lib/python3.9/site-packages/websockets/legacy/protocol.py", line 919, in read_data_frame
    [HIDDEN]
  File "venv/lib/python3.9/site-packages/websockets/legacy/protocol.py", line 726, in ensure_open
    raise self.connection_closed_exc()
websockets.exceptions.ConnectionClosedError: code = 1006 (connection closed abnormally [internal]), no reason
```

As far as I can tell the exception never passes through the application thus providing the application no opportunity to catch it.

[HIDDEN] However, I am not familiar enough with the library to know if it could be a symptom of a problem elsewhere.

What do you think?

It seems to be caused by connecting a client that does not receive any of the messages sent by the server eventually triggering a ping timeout. Not sure if it happens on client side or server side since in my testing so far both run in the same process.

### Additional contract requirements

- If the connection closes before the protocol can automatically answer an incoming ping, the resulting connection-closed exception must not be reported as an error.
