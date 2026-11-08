utils.get_current_url() fails to parse IPv6 IP address
(This has similar smells to it as #2903)

By the looks of it, https://github.com/pallets/werkzeug/blob/9a69323223616188d50f337ba03831a944e82d6f/src/werkzeug/sansio/utils.py#L97-L97 when called from https://github.com/pallets/werkzeug/blob/9a69323223616188d50f337ba03831a944e82d6f/src/werkzeug/sansio/request.py#L205-L210 isn't coping with a bare IPv6 address?

```
ValueError: Port could not be cast to integer value as '1901:0:3dbd::'
    raise ValueError(f"Port could not be cast to integer value as {port!r}")
  File "/usr/local/lib/python3.11/urllib/parse.py", line 182, in port
       ^^^^^^^^^^
    if parts.port:
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/urls.py", line 98, in uri_to_iri
           ^^^^^^^^^^^^^^^^^^^^^^^^
    return uri_to_iri("".join(url))
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/sansio/utils.py", line 137, in get_current_url
           ^^^^^^^^^^^^^^^^
    return get_current_url(
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/sansio/request.py", line 210, in url
            ^^^^^^^^^^^^^^
    value = self.fget(obj)  # type: ignore
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/utils.py", line 107, in __get__
                  ^^^^^^^^^^^^^^^^^
    "requestUrl": flask.request.url,
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/_helpers.py", line 79, in get_request_data_from_flask
                                                                    ^^^^^^^^^
    http_request, http_trace_id, http_span_id, http_trace_sampled = checker()
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/_helpers.py", line 273, in get_request_data
        ^^^^^^^^^^^^^^^^^^
    ) = get_request_data()
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/handlers.py", line 98, in filter
             ^^^^^^^^^^^^^^^^
    result = f.filter(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 830, in filter
         ^^^^^^^^^^^^^^^^^^^
    rv = self.filter(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 974, in handle
    hdlr.handle(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1706, in callHandlers
    self.callHandlers(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1644, in handle
    self.handle(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1634, in _log
    self._log(ERROR, msg, args, **kwargs)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1518, in error
    self.logger.error(
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1414, in log_exception
    self.log_exception(exc_info)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1393, in handle_exception
               ^^^^^^^^^^^^^^^^^^^^^^^^
    response = self.handle_exception(e)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 2193, in wsgi_app
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return wsgi_app(environ, start_response)
  File "/osv/gcp/appengine/main.py", line 37, in middleware
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return self.application(environ, start_response)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/whitenoise/base.py", line 81, in __call__
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return self.wsgi_app(environ, start_response)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 2213, in __call__
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    respiter = self.wsgi(environ, resp.start_response)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/gunicorn/workers/gthread.py", line 334, in handle_request
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Traceback (most recent call last):  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/gunicorn/workers/gthread.py", line 282, in handle    keepalive = self.handle_request(req, conn)
During handling of the above exception, another exception occurred:
ValueError: Port could not be cast to integer value as '1901:0:3dbd::'
    raise ValueError(f"Port could not be cast to integer value as {port!r}")
  File "/usr/local/lib/python3.11/urllib/parse.py", line 182, in port
       ^^^^^^^^^^
    if parts.port:
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/urls.py", line 98, in uri_to_iri
           ^^^^^^^^^^^^^^^^^^^^^^^^
    return uri_to_iri("".join(url))
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/sansio/utils.py", line 137, in get_current_url
           ^^^^^^^^^^^^^^^^
    return get_current_url(
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/sansio/request.py", line 210, in url
            ^^^^^^^^^^^^^^
    value = self.fget(obj)  # type: ignore
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/utils.py", line 107, in __get__
                  ^^^^^^^^^^^^^^^^^
    "requestUrl": flask.request.url,
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/_helpers.py", line 79, in get_request_data_from_flask
                                                                    ^^^^^^^^^
    http_request, http_trace_id, http_span_id, http_trace_sampled = checker()
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/_helpers.py", line 273, in get_request_data
        ^^^^^^^^^^^^^^^^^^
    ) = get_request_data()
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/google/cloud/logging_v2/handlers/handlers.py", line 98, in filter
             ^^^^^^^^^^^^^^^^
    result = f.filter(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 830, in filter
         ^^^^^^^^^^^^^^^^^^^
    rv = self.filter(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 974, in handle
    hdlr.handle(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1706, in callHandlers
    self.callHandlers(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1644, in handle
    self.handle(record)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1634, in _log
    self._log(INFO, msg, args, **kwargs)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 1489, in info
    root.info(msg, *args, **kwargs)
  File "/usr/local/lib/python3.11/logging/__init__.py", line 2141, in info
    logging.info('Handled %s - Path attempted: %s', error, request.path)
  File "/osv/gcp/appengine/frontend_handlers.py", line 707, in not_found_error
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return self.ensure_sync(handler)(e)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1281, in handle_http_exception
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return self.handle_http_exception(e)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1341, in handle_user_exception
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    rv = self.handle_user_exception(e)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1486, in full_dispatch_request
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Traceback (most recent call last):  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 2190, in wsgi_app    response = self.full_dispatch_request()
During handling of the above exception, another exception occurred:
werkzeug.exceptions.NotFound: 404 Not Found: The requested URL was not found on the server. If you entered the URL manually please check your spelling and try again.
    raise self.mapping[code](*args, **kwargs)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/werkzeug/exceptions.py", line 863, in __call__
    current_app.aborter(code, *args, **kwargs)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/helpers.py", line 277, in abort
    abort(404)
  File "/osv/gcp/appengine/frontend_handlers.py", line 254, in vulnerability_redirector
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    return self.ensure_sync(self.view_functions[rule.endpoint])(**view_args)
  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1469, in dispatch_request
         ^^^^^^^^^^^^^^^^^^^^^^^
Traceback (most recent call last):  File "/osv/gcp/appengine/.venv/lib/python3.11/site-packages/flask/app.py", line 1484, in full_dispatch_request    rv = self.dispatch_request()
```

Environment:

- Python version: 3.11
- Werkzeug version: 3.0.6

### Additional contract requirements

- When the ``Host`` header is absent and the WSGI ``SERVER_NAME`` (the
  ``server`` argument) is an IPv6 address, :func:`werkzeug.sansio.utils.get_host`
  returns the address wrapped in ``[]``, with the port appended after the
  closing bracket, for example ``[::1]:8080``. This matches the format a
  ``Host`` header would use.
- Consequently, :func:`werkzeug.sansio.utils.get_current_url` (and therefore
  ``Request.url``) produces a valid URL for such a request, for example
  ``http://[::1]:8080/``, instead of raising ``ValueError``.
