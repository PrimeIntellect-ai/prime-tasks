client: posting multipart-formdata and integer
the multipart-formdata is not working with integer values, i spend many times to find-out what is the problem:
## Actual behaviour

```
Traceback (most recent call last):
  File "/home/vahid/workspace/aiohttp/aiohttp/client_reqrep.py", line 390, in write_bytes
    result = stream.send(value)
  File "/home/vahid/workspace/aiohttp/aiohttp/helpers.py", line 188, in _gen_form_data
    yield from self._writer.serialize()
  File "/home/vahid/workspace/aiohttp/aiohttp/multipart.py", line 958, in serialize
    yield from part.serialize()
  File "/home/vahid/workspace/aiohttp/aiohttp/multipart.py", line 759, in serialize
    yield from self._maybe_encode_stream(self._serialize_obj())
  File "/home/vahid/workspace/aiohttp/aiohttp/multipart.py", line 772, in _serialize_obj
    return self._serialize_default(obj)
  File "/home/vahid/workspace/aiohttp/aiohttp/multipart.py", line 804, in _serialize_default
    raise TypeError('unknown body part type %r' % type(obj))
TypeError: unknown body part type <class 'int'>

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/opt/pycharm-2016.1.1/helpers/pydev/pydevd.py", line 1531, in <module>
    globals = debugger.run(setup['file'], None, None, is_module)
  File "/opt/pycharm-2016.1.1/helpers/pydev/pydevd.py", line 938, in run
    pydev_imports.execfile(file, globals, locals)  # execute the script
  File "/opt/pycharm-2016.1.1/helpers/pydev/_pydev_imps/_pydev_execfile.py", line 18, in execfile
    exec(compile(contents+"\n", file, 'exec'), glob, loc)
  File "/home/vahid/workspace/hazelnut/practice/formdata.py", line 26, in <module>
    loop.run_until_complete(main())
  File "/usr/local/lib/python3.5/asyncio/base_events.py", line 337, in run_until_complete
    return future.result()
  File "/usr/local/lib/python3.5/asyncio/futures.py", line 274, in result
    raise self._exception
  File "/usr/local/lib/python3.5/asyncio/tasks.py", line 241, in _step
    result = coro.throw(exc)
  File "/home/vahid/workspace/hazelnut/practice/formdata.py", line 21, in main
    await session.post(url, data=data)
  File "/home/vahid/workspace/aiohttp/aiohttp/client.py", line 537, in __await__
    resp = yield from self._coro
  File "/home/vahid/workspace/aiohttp/aiohttp/client.py", line 191, in _request
    yield from resp.start(conn, read_until_eof)
  File "/home/vahid/workspace/aiohttp/aiohttp/client_reqrep.py", line 619, in start
    message = yield from httpstream.read()
  File "/home/vahid/workspace/aiohttp/aiohttp/streams.py", line 592, in read
    result = yield from super().read()
  File "/home/vahid/workspace/aiohttp/aiohttp/streams.py", line 447, in read
    yield from self._waiter
  File "/usr/local/lib/python3.5/asyncio/futures.py", line 358, in __iter__
    yield self  # This tells Task to wait for completion.
  File "/usr/local/lib/python3.5/asyncio/tasks.py", line 290, in _wakeup
    future.result()
  File "/usr/local/lib/python3.5/asyncio/futures.py", line 274, in result
    raise self._exception
aiohttp.errors.ClientRequestError: Can not write request body for http://example.org/
```
## Steps to reproduce

```
import asyncio
import aiohttp
import io


sample_data = {
    'host': 'localhost',
    'label': 'DefaultNode',
    'quality': 100,
    'capacity': 100000,
}

async def main():
    url = 'http://example.org'
    data = aiohttp.FormData()
    data.add_field('file', io.StringIO('Sample text file'), content_type='text/plain')
    for k, v in sample_data.items():
        data.add_field(k, v)

    with aiohttp.ClientSession() as session:
        await session.post(url, data=data)


if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())
```
## My environment

os: Ubuntu 14.04
python 3.5.1
aiohttp: master: f180199

### Additional contract requirements

- Appending a value to a multipart writer whose type cannot be serialized as a body part (for example a plain `object()`) must raise `TypeError` at the time of the `append` call, not later when the body is serialized or sent.
- Appending an integer value must not make sending the form fail: the value is either rejected with `TypeError` at the time of `append`, or it is serialized into the body as its textual value.
