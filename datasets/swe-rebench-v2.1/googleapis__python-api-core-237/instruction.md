retry ChunkedEncodingError by default
Per https://github.com/psf/requests/issues/4771, ChunkedEncodingError is a kind of transport-layer error. They don't classify it as a connection error because it's caused by a "misbehaving server", but in our case it's likely due to a transient issue somewhere in the server stack. Retrying is likely to help.

#### Stack trace

See: https://github.com/googleapis/python-bigquery-storage/issues/242

```
[POST]
Traceback (most recent call last):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 696, in _update_chunk_length
    self.chunk_left = int(line, 16)
  ValueError: invalid literal for int() with base 16: b''

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 436, in _error_catcher
    yield
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 763, in read_chunked
    self._update_chunk_length()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 700, in _update_chunk_length
    raise httplib.IncompleteRead(line)
  http.client.IncompleteRead: IncompleteRead(0 bytes read)

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/requests/models.py", line 751, in generate
    for chunk in self.raw.stream(chunk_size, decode_content=True):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 571, in stream
    for line in self.read_chunked(amt, decode_content=decode_content):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 792, in read_chunked
    self._original_response.close()
  File "/opt/python3.9/lib/python3.9/contextlib.py", line 135, in __exit__
    self.gen.throw(type, value, traceback)
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/urllib3/response.py", line 454, in _error_catcher
    raise ProtocolError("Connection broken: %r" % e, e)
  urllib3.exceptions.ProtocolError: ('Connection broken: IncompleteRead(0 bytes read)', IncompleteRead(0 bytes read))

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/app.py", line 2447, in wsgi_app
    response = self.full_dispatch_request()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/app.py", line 1952, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/app.py", line 1821, in handle_user_exception
    reraise(exc_type, exc_value, tb)
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/_compat.py", line 39, in reraise
    raise value
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/app.py", line 1950, in full_dispatch_request
    rv = self.dispatch_request()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/flask/app.py", line 1936, in dispatch_request
    return self.view_functions[rule.endpoint](**req.view_args)
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/functions_framework/__init__.py", line 152, in view_func
    function(data, context)
  File "/workspace/common/functions.py", line 61, in wrapper
    raise e
  File "/workspace/common/functions.py", line 54, in wrapper
    response = wrapped_func(*args, **kwargs)
  File "/workspace/main.py", line 533, in controller
    status = create_files(contex_bdp)
  File "/workspace/main.py", line 346, in create_files
    for row in result:
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/api_core/page_iterator.py", line 214, in _items_iter
    for page in self._page_iter(increment=False):
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/api_core/page_iterator.py", line 253, in _page_iter
    page = self._next_page()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/api_core/page_iterator.py", line 382, in _next_page
    response = self._get_next_page_response()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/cloud/bigquery/table.py", line 1541, in _get_next_page_response
    return self.api_request(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/cloud/bigquery/client.py", line 686, in _call_api
    return call()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/api_core/retry.py", line 285, in retry_wrapped_func
    return retry_target(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/api_core/retry.py", line 188, in retry_target
    return target()
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/cloud/_http.py", line 473, in api_request
    response = self._make_request(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/cloud/_http.py", line 337, in _make_request
    return self._do_request(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/cloud/_http.py", line 375, in _do_request
    return self.http.request(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/google/auth/transport/requests.py", line 482, in request
    response = super(AuthorizedSession, self).request(
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/requests/sessions.py", line 530, in request
    resp = self.send(prep, **send_kwargs)
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/requests/sessions.py", line 685, in send
    r.content
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/requests/models.py", line 829, in content
    self._content = b''.join(self.iter_content(CONTENT_CHUNK_SIZE)) or b''
  File "/layers/google.python.pip/pip/lib/python3.9/site-packages/requests/models.py", line 754, in generate
    raise ChunkedEncodingError(e) requests.exceptions.ChunkedEncodingError: ('Connection broken: IncompleteRead(0 bytes read)', IncompleteRead(0 bytes read))
```
