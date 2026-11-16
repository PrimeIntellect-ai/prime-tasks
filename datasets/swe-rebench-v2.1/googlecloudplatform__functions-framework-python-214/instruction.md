functions-framework --debug exits if you save with a syntax error
Steps to reproduce:

* Start things up normally
```
functions-framework \
    --source=cloud_function/main.py \
    --target=hello_get \
    --host=localhost \
    --port=18000 \
    --debug
```
<details><summary>This starts up as expected:</summary>
```
 * Serving Flask app 'hello_get' (lazy loading)
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: on
WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
 * Running on http://localhost:18000
Press CTRL+C to quit
 * Restarting with watchdog (fsevents)
 * Debugger is active!
 * Debugger PIN: 104-682-644
```
</details>

Make a change that introduces a syntax error, and you get:
```
 * Detected change in '/Users/david/src/opvia/app/scripts_v3/cloud_function/main.py', reloading
 * Restarting with watchdog (fsevents)
Traceback (most recent call last):
  File "/Users/david/src/opvia/app/.venv/bin/functions-framework", line 8, in <module>
    sys.exit(_cli())
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/click/core.py", line 1130, in __call__
    return self.main(*args, **kwargs)
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/click/core.py", line 1055, in main
    rv = self.invoke(ctx)
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/click/core.py", line 1404, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/click/core.py", line 760, in invoke
    return __callback(*args, **kwargs)
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/functions_framework/_cli.py", line 37, in _cli
    app = create_app(target, source, signature_type)
  File "/Users/david/src/opvia/app/.venv/lib/python3.10/site-packages/functions_framework/__init__.py", line 289, in create_app
    spec.loader.exec_module(source_module)
  File "<frozen importlib._bootstrap_external>", line 879, in exec_module
  File "<frozen importlib._bootstrap_external>", line 1017, in get_code
  File "<frozen importlib._bootstrap_external>", line 947, in source_to_code
  File "<frozen importlib._bootstrap>", line 241, in _call_with_frames_removed
  File "/Users/david/src/opvia/app/scripts_v3/cloud_function/main.py", line 11
    ///
    ^^
SyntaxError: invalid syntax
```

and the process exits

Potential solution:

Apparently this used to be an issue in Flask, but isn't anymore (see https://stackoverflow.com/a/68445450 ). I did some digging to work out how they fixed it, and I think I have a solution:

[HIDDEN]
[HIDDEN]

### Additional contract requirements

- If loading the source fails during a debug-mode reload, report the error so the developer can see why loading failed, and do not terminate the Functions Framework process.
- After a reload-time source-load error, requests to the app must fail with HTTP 500.
- Outside a reloader run, a source-load error must still be raised during app creation.
