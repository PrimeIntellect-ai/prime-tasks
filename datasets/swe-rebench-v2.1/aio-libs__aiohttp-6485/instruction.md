AttributeError on Payload
### Describe the bug

Is this actually a bug in aiohttp? https://github.com/aio-libs/aiohttp-devtools/issues/251

`response._body` at this point is actually a `StringPayload`, which does not have a `decode` attribute:
https://github.com/aio-libs/aiohttp/blob/3.8/aiohttp/web_response.py#L694

```
Traceback (most recent call last):
  File "/home/ubuntu/.local/lib/python3.8/site-packages/aiohttp/web_protocol.py", line 514, in start
    resp, reset = await task
  File "/home/ubuntu/.local/lib/python3.8/site-packages/aiohttp/web_protocol.py", line 460, in _handle_request
    reset = await self.finish_response(request, resp, start_time)
  File "/home/ubuntu/.local/lib/python3.8/site-packages/aiohttp/web_protocol.py", line 619, in finish_response
    self.log_access(request, resp, start_time)
  File "/home/ubuntu/.local/lib/python3.8/site-packages/aiohttp/web_protocol.py", line 398, in log_access
    self.access_logger.log(request, response, self._loop.time() - time)
  File "/home/ubuntu/hacking/aiohttp-devtools/aiohttp_devtools/runserver/log_handlers.py", line 36, in log
    self.logger.info(msg, extra=self.extra(request, response, time))
  File "/home/ubuntu/hacking/aiohttp-devtools/aiohttp_devtools/runserver/log_handlers.py", line 60, in extra
    response_body=parse_body(response.text or response.body, 'response body'),
  File "/home/ubuntu/.local/lib/python3.8/site-packages/aiohttp/web_response.py", line 694, in text
    return self._body.decode(self.charset or "utf-8")
AttributeError: 'StringPayload' object has no attribute 'decode'
```

### Additional contract requirements

- ``MultipartWriter.decode(encoding="utf-8", errors="strict")`` returns a textual representation of the multipart body. For each part it emits the boundary marker ``"--" + boundary + "\n"``, followed by the part's headers decoded with the given encoding and errors, followed by the part's decoded body. For a writer with boundary ``"x"`` containing a single ``StringPayload("test")`` part, the result is exactly ``--x\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 4\r\n\r\ntest``.
