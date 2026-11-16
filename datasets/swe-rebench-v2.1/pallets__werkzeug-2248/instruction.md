Empty response with failure from ProcessPoolExecutor
When a flask app uses a ProcessPoolExecutor and one of its tasks fails, werkzeug can't handle the stack trace.

```
from flask import Flask
import concurrent.futures

app = Flask(__name__)

def fail():
    raise ValueError('Failed')

@app.route("/")
def test():
    executor = concurrent.futures.ProcessPoolExecutor(max_workers=1)
    future = executor.submit(fail)
    return future.result()

if __name__ == '__main__':
    app.run(debug=True)
```

```
$ curl http://localhost:5000
curl: (52) Empty reply from server
```

```
Exception occurred during processing of request from ('127.0.0.1', 52594)
concurrent.futures.process._RemoteTraceback:
"""
Traceback (most recent call last):
  File "/home/kjurka/tmp/mclatest/lib/python3.9/concurrent/futures/process.py", line 243, in _process_worker
    r = call_item.fn(*call_item.args, **call_item.kwargs)
  File "/home/kjurka/tmp/mclatest/flask_processpool.py", line 7, in fail
    raise ValueError('Failed')
ValueError: Failed
"""

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/__init__.py", line 309, in debug_application
    app_iter = self.app(environ, start_response)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 2088, in __call__
    return self.wsgi_app(environ, start_response)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 2073, in wsgi_app
    response = self.handle_exception(e)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 2070, in wsgi_app
    response = self.full_dispatch_request()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 1515, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 1513, in full_dispatch_request
    rv = self.dispatch_request()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/flask/app.py", line 1499, in dispatch_request
    return self.ensure_sync(self.view_functions[rule.endpoint])(**req.view_args)
  File "/home/kjurka/tmp/mclatest/flask_processpool.py", line 13, in test
    return future.result()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/concurrent/futures/_base.py", line 445, in result
    return self.__get_result()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/concurrent/futures/_base.py", line 390, in __get_result
    raise self._exception
ValueError: Failed

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/serving.py", line 319, in run_wsgi
    execute(self.server.app)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/serving.py", line 310, in execute
    for data in application_iter:
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/__init__.py", line 316, in debug_application
    traceback = get_current_traceback(
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 182, in get_current_traceback
    tb.filter_hidden_frames()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 248, in filter_hidden_frames
    group.filter_hidden_frames()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 388, in filter_hidden_frames
    [HIDDEN]
  File "/home/kjurka/tmp/mclatest/lib/python3.9/socketserver.py", line 683, in process_request_thread
    self.finish_request(request, client_address)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/socketserver.py", line 747, in __init__
    self.handle()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/serving.py", line 342, in handle
    BaseHTTPRequestHandler.handle(self)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/http/server.py", line 427, in handle
    self.handle_one_request()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/serving.py", line 374, in handle_one_request
    self.run_wsgi()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/serving.py", line 327, in run_wsgi
    traceback = get_current_traceback(ignore_system_exceptions=True)
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 182, in get_current_traceback
    tb.filter_hidden_frames()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 248, in filter_hidden_frames
    group.filter_hidden_frames()
  File "/home/kjurka/tmp/mclatest/lib/python3.9/site-packages/werkzeug/debug/tbtools.py", line 388, in filter_hidden_frames
    [HIDDEN]
```


Environment:

- Python version: 3.9.5
- Werkzeug version: 2.0.1
- Flask version: 2.0.1

### Additional contract requirements

- When a task run by a `ProcessPoolExecutor` raises an exception while a Flask app is served with Werkzeug's debugger enabled, traceback processing must not raise a secondary error. The client must receive the debugger's error response rather than an empty reply.
