[athena] Object of type WorkGroup is not JSON serializable
Hi, latest docker image of motoserver (`motoserver/moto:latest`) uploaded on Dec 09th 2024 contains an issue related to type serialization.
The issue is not present in previous version `5.0.22`.

When calling Athena endpoint `get_query_execution`, the following error is raised:
```
TypeError: Object of type WorkGroup is not JSON serializable
```

Here's the full traceback:
```
Traceback (most recent call last):
  File "/usr/local/lib/python3.11/site-packages/werkzeug/serving.py", line 370, in run_wsgi
    execute(self.server.app)
  File "/usr/local/lib/python3.11/site-packages/werkzeug/serving.py", line 331, in execute
    application_iter = app(environ, start_response)
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/moto_server/werkzeug_app.py", line 261, in __call__
    return backend_app(environ, start_response)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 1536, in __call__
    return self.wsgi_app(environ, start_response)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 1514, in wsgi_app
    response = self.handle_exception(e)
               ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask_cors/extension.py", line 194, in wrapped_function
    return cors_after_request(app.make_response(f(*args, **kwargs)))
                                                ^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 1511, in wsgi_app
    response = self.full_dispatch_request()
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 919, in full_dispatch_request
    rv = self.handle_user_exception(e)
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask_cors/extension.py", line 194, in wrapped_function
    return cors_after_request(app.make_response(f(*args, **kwargs)))
                                                ^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 917, in full_dispatch_request
    rv = self.dispatch_request()
         ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/flask/app.py", line 902, in dispatch_request
    return self.ensure_sync(self.view_functions[rule.endpoint])(**view_args)  *** type: ignore[no-any-return]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/core/utils.py", line 112, in __call__
    result = self.callback(request, request.url, dict(request.headers))
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/core/responses.py", line [291](https://github.com/docker/saas-mega/actions/runs/12242202016/job/34149046626?pr=14868#step:21:292), in dispatch
    return cls()._dispatch(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/core/responses.py", line 503, in _dispatch
    return self.call_action()
           ^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/core/responses.py", line 591, in call_action
    response = method()
               ^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/moto/athena/responses.py", line 99, in get_query_execution
    return json.dumps(result)
           ^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/json/__init__.py", line 231, in dumps
    return _default_encoder.encode(obj)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/json/encoder.py", line 200, in encode
    chunks = self.iterencode(o, _one_shot=True)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/json/encoder.py", line 258, in iterencode
    return _iterencode(o, 0)
           ^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/json/encoder.py", line 180, in default
    raise TypeError(f'Object of type {o.__class__.__name__} '
TypeError: Object of type WorkGroup is not JSON serializable
```
