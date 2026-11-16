Python 3.10: tests fail due to `DeprecationWarning: There is no current event loop`
The test suite is failing against Python 3.10.0b1 due to a lot of `DeprecationWarning`s, e.g.:

```pytb
==================================================================== FAILURES ====================================================================
________________________________________________________________ test_basic_async ________________________________________________________________
tests/test_async.py:29: in test_basic_async
    rv = run(func())
tests/test_async.py:17: in run
    loop = asyncio.get_event_loop()
E   DeprecationWarning: There is no current event loop
______________________________________________________________ test_await_on_calls _______________________________________________________________
tests/test_async.py:45: in test_await_on_calls
    rv = run(func())
tests/test_async.py:17: in run
    loop = asyncio.get_event_loop()
E   DeprecationWarning: There is no current event loop
_______________________________________________________ test_await_on_calls_normal_render ________________________________________________________
tests/test_async.py:58: in test_await_on_calls_normal_render
    rv = t.render(async_func=async_func, normal_func=normal_func)
.tox/py310/lib/python3.10/site-packages/jinja2/environment.py:1281: in render
    loop = asyncio.get_event_loop()
E   DeprecationWarning: There is no current event loop
[...]
```

To reproduce:
```
tox -e py310
```

Environment:

- Python version: 3.10.0b1
- Jinja version: ab7840328f3c6303b4509972f7751e9ab1ee36c7
