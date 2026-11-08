function `append_slash_redirect` misredirects
file `test.py`

```python
from flask import Flask, request
from werkzeug.utils import append_slash_redirect

app = Flask("test")

@app.route('/<path:path>')
def r(path):
    if not path.endswith('/'):
        return append_slash_redirect(request.environ)
    return path
```
run `FLASK_APP=test.py flask run`

A request for http://localhost:5000/parent/child gives a redirect that browsers interpret as `http://localhost:5000/parent/parent/child/`

Expecting a redirect that browsers interpret as `http://localhost:5000/parent/child/`

Possible solution:

[HIDDEN] [HIDDEN]
[HIDDEN]
