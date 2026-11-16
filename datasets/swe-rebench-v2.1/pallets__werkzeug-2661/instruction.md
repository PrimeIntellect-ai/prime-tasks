plus (+) in query args converted to space
# Summary

In #2608 some functions were changed to use `urllib.parse.quote`. Note that there exists `urllib.parse.quote_plus`, which is almost the same, but handles the plus and space characters differently. [HIDDEN]

Code that was working for me yesterday with the older version of werkzeug is now not working with the newest version.


# Minimum Working Example

## Steps to reproduce

```
from flask import Flask, jsonify, request
import re

app = Flask(__name__)

@app.route('/v1/telemetry', methods=['GET'])
def telemetry():
    print(f"telemetry received")
    print(f"telemetry received args {request.args}")
    mystr = request.args['mystr']
    print(f"telemetry received {mystr}")
    pat = r"[a-z]\+[a-z]"
    assert re.match(pat, mystr)

    # XSS vulnerable of course
    # this is just a MWE
    return jsonify({'echo': mystr})

app.testing = True
app.debug = True


client = app.test_client()
resp = client.get('/v1/telemetry', query_string={'mystr': 'a+b'})
assert resp.status_code == 200
assert resp.json['echo'] == 'a+b'

```

```
pip3 install werkzeug==2.3.0 flask
```

```
python3 main.py
```

## Expected behavior

Script runs without error. The assertions passes.

## Actual Behavior

```
Traceback (most recent call last):
  File "main.py", line 23, in <module>
    resp = client.get('/v1/telemetry', query_string={'mystr': 'a+b'})
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/werkzeug/test.py", line 1241, in get
    return self.open(*args, **kw)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/testing.py", line 227, in open
    response = super().open(
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/werkzeug/test.py", line 1195, in open
    response = self.run_wsgi_app(request.environ, buffered=buffered)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/werkzeug/test.py", line 1069, in run_wsgi_app
    rv = run_wsgi_app(self.application, environ, buffered=buffered)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/werkzeug/test.py", line 1343, in run_wsgi_app
    app_rv = app(environ, start_response)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 2552, in __call__
    return self.wsgi_app(environ, start_response)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 2532, in wsgi_app
    response = self.handle_exception(e)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 2529, in wsgi_app
    response = self.full_dispatch_request()
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 1825, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 1823, in full_dispatch_request
    rv = self.dispatch_request()
  File "/home/ec2-user/environment/scratch/schemathesis/venv/lib/python3.8/site-packages/flask/app.py", line 1799, in dispatch_request
    return self.ensure_sync(self.view_functions[rule.endpoint])(**view_args)
  File "main.py", line 13, in telemetry
    assert re.match(pat, mystr)
AssertionError
```

If you downgrade to the previous version of werkzeug:

```
pip3 install werkzeug==2.2.3
```

Then it does work.
(The script runs without throwing any exceptions)

# Environment

- Python version: 3.8.11
- Werkzeug version:
  -  2.2.3 - works
  -  2.3.0 - doesn't work

### Additional contract requirements

- A literal `+` in a value passed through the test client's `query_string` mapping must survive the request as `+`, so that the example's view reads `request.args["mystr"]` as `a+b` and the response echoes `a+b` (not `a b`).
- When the router builds a URL from unknown query arguments, a literal `+` in a value must be percent-encoded as `%2B`; for example, building with `{"v": "1+2"}` produces the query string `?v=1%2B2`.
