[Bug] 22.9.0 - TypeError: <class 'str'> is not JSON serializable for OpenAPI blueprint
**Describe the bug**

I've upgraded my [project](https://gitlab.com/morph027/python-signal-cli-rest-api/-/tree/release-22.9.1) to 22.9.0 and when trying to open swagger UI, it fails with the following stacktrace:

```
[2022-09-29 17:12:42 +0000] [7] [INFO]
  ┌─────────────────────────────────────────────────────────────────────────────────────┐
  │                                    Sanic v22.9.0                                    │
  │                           Goin' Fast @ http://0.0.0.0:8080                          │
  ├───────────────────────┬─────────────────────────────────────────────────────────────┤
  │                       │     mode: production, single worker                         │
  │     ▄███ █████ ██     │   server: sanic, HTTP/1.1                                   │
  │    ██                 │   python: 3.8.10                                            │
  │     ▀███████ ███▄     │ platform: Linux-5.19.5-051905-generic-x86_64-with-glibc2.29 │
  │                 ██    │ packages: sanic-routing==22.8.0, sanic-ext==22.9.0          │
  │    ████ ████████▀     │                                                             │
  │                       │                                                             │
  │ Build Fast. Run Fast. │                                                             │
  └───────────────────────┴─────────────────────────────────────────────────────────────┘

[2022-09-29 17:12:42 +0000] [7] [WARNING] Sanic is running in PRODUCTION mode. Consider using '--debug' or '--dev' while actively developing your application.
[2022-09-29 17:12:42 +0000] [17] [INFO] Sanic Extensions:
[2022-09-29 17:12:42 +0000] [17] [INFO]   > injection [0 added]
[2022-09-29 17:12:42 +0000] [17] [INFO]   > openapi [http://0.0.0.0:8080/docs]
[2022-09-29 17:12:42 +0000] [17] [INFO]   > http
[2022-09-29 17:12:42 +0000] [17] [INFO] Starting worker [17]
[2022-09-29 17:12:45 +0000] [17] [ERROR] Exception occurred while handling uri: 'http://localhost:8080/docs/openapi.json'
Traceback (most recent call last):
  File "handle_request", line 94, in handle_request
  File "/var/lib/python-signal-cli-rest-api/.venv/lib/python3.8/site-packages/sanic_ext/extensions/openapi/blueprint.py", line 52, in spec
    return json(SpecificationBuilder().build(request.app).serialize())
  File "/var/lib/python-signal-cli-rest-api/.venv/lib/python3.8/site-packages/sanic/response.py", line 244, in json
    dumps(body, **kwargs),
TypeError: <class 'str'> is not JSON serializable
```

**To Reproduce**

Not sure if this happens on my project only. Will try to re-create with a blank dummy project.

**Expected behavior**

Render openapi.json

### Additional contract requirements

- The OpenAPI specification document served by the OpenAPI blueprint must render as JSON (a successful response containing the specification) when a documented request body uses a schema dictionary that contains type annotations, instead of raising a JSON serialization error.
- The `openapi.definition` decorator accepts a `body` mapping whose content-type value may be a dictionary that contains type annotations (for example `{"application/json": {"name": str}}`), including when the annotations appear inside a nested `schema` entry; such a dictionary is rendered as an object schema whose properties reflect the annotated names.
- Add a public function `flat_values(item)` in module `sanic_ext.utils.typing` that returns a `set` containing every leaf (non-container) value found recursively in the given mapping or iterable, handling nested dictionaries and lists at arbitrary depth.
- Add a public function `contains_annotations(d)` in module `sanic_ext.utils.typing` that returns `True` when any value directly in the dictionary `d` is a class object or a generic type, and `False` otherwise.
