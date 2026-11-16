v2.2.0 breaks previous URL map logic for url-encoded path segments containing %2F
Version 2.2.0 seems to change the way url-encoded path segments (specifically paths which contain the escape sequence for `/`, `%2F`) are handled in rules/maps in the routing module.

Here's a self-contained example demonstrating the difference in routing behavior, save this in `werkzeug_test.py` for example:
```python
from werkzeug.routing import Map, Rule
from werkzeug.wrappers import Request, Response


class PathTester:

    URL_MAP = Map(
        [
            Rule(
                "/<path:some_path>/some_route",
                endpoint="simple_route",
            ),
            Rule(
                "/<path:some_path>/<segment_a>/<segment_b>",
                endpoint="complex_route",
            ),
        ]
    )

    def on_simple_route(self, request, some_path):
        return Response("Matched simple route")

    def on_complex_route(self, request, some_path, segment_a, segment_b):
        return Response("Matched complex route")

    def dispatch_request(self, request):
        adapter = self.URL_MAP.bind_to_environ(request.environ)
        endpoint, values = adapter.match()
        return getattr(self, f"on_{endpoint}")(request, **values)

    def wsgi_app(self, environ, start_response):
        request = Request(environ)
        response = self.dispatch_request(request)
        return response(environ, start_response)

    def __call__(self, environ, start_response):
        return self.wsgi_app(environ, start_response)


if __name__ == "__main__":
    from werkzeug.serving import run_simple
    run_simple("127.0.0.1", 5000, PathTester())
```

Running this example using werkzeug 2.1.2:
```shell
$ pip install --upgrade Werkzeug==2.1.2
$ python werkzeug_test.py

# … in another terminal

$ curl http://localhost:5000/my%2Fpath/some_route
Matched simple route
```

Now, running this example using werkzeug 2.2.0:
```shell
$ pip install --upgrade Werkzeug==2.2.0
$ python werkzeug_test.py

# … in another terminal

$ curl http://localhost:5000/my%2Fpath/some_route
Matched complex route
```

Environment:
- Python version: 3.9.13
- Werkzeug version: 2.2.0

### Additional contract requirements

For the demonstrated request `/my%2Fpath/some_route`, routing must select the `simple_route` endpoint and return the captured `some_path` value as the decoded string `my/path`.
