Server closes connection if wrong type returned by handler
🐞 **Describe the bug**
<!-- A clear and concise description of what the bug is, on the next line. -->
Server closes session if handler returns anything else that `Response` instance.

💡 **To Reproduce**
<!-- How to reproduce the behavior?

For example:
1. Have certain environment
2. Run given code snippet in a certain way
3. See some behavior described

Add these steps below this comment: -->
```python
from aiohttp import web


async def handler(req):
    return 1

app = web.Application()
app.add_routes([web.get("/", handler)])
web.run_app(app)
```

```bash
~ curl localhost:8080
curl: (52) Empty reply from server
```

💡 **Expected behavior**
<!-- A clear and concise description of what you expected to happen. -->
Error message in console and returned status 500.

📋 **Your version of the Python**
<!-- Attach your version of the Python. -->
```console
$ python --version
Python 3.8.1
```

📋 **Your version of the aiohttp/yarl/multidict distributions**
<!-- Attach your version of the distributions in the code blocks below. -->
Tested with aiohttp `3.6.2` and `master` branch fresh installations.

### Additional contract requirements

- When a handler returns a value that is not a `StreamResponse` (including `None`),
  the server must respond with HTTP status 500 and call `logger.exception` or
  `logger.error` on the logger configured on the application runner.
