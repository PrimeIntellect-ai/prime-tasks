doctest causes a working out of context RuntimeError with request
Migrating from Flask 2.1 to 2.2 failed a few unit tests of mine. It looks like we can no longer import `flask.request` top level in a test file (reproduced across Python 3.7, 3.8, 3.9, 3.10):

```python
from flask import Flask
from flask import request

def test_something():
    assert True
```

This gives a `RuntimeError`:

```
E   RuntimeError: Working outside of request context.
E
E   This typically means that you attempted to use functionality that needed
E   an active HTTP request. Consult the documentation on testing for
E   information about how to avoid this problem.
```

On my side the fix was simple: importing `flask.request` outside of the global scope, just when I actually need it (my actual tests create small Flask apps to test a client).

Edit: forgot to mention that this only occurs when pytest is run with `--doctest-modules`

### Additional contract requirements

- With pytest running in doctest-modules mode, importing a request proxy at module scope must not raise a request-context `RuntimeError` when doctest inspects it.
- For a `LocalProxy` that resolves to a bound target, reading `__wrapped__` must yield the target's own `__wrapped__` value when it has one, and must raise `AttributeError` when it does not.
