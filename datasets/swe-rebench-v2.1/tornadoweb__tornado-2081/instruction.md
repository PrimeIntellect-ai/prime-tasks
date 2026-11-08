Autoreload fails for __main__ module with relative imports
Let's assume we have a Tornado app with the following structure

```
testapp/
  __init__.py
  __main__.py
  foo.py
  ...
```

where `__main__` contains a relative import like `from .foo import Bar`.

Running the app with `python -m testapp` will work as expected. If autoreload is enabled, a reload will however fail with the following exception:

```
SystemError: Parent module '' not loaded, cannot perform relative import
```

As explained in the source of autoreload, this happens because the command line arguments are transformed by Python from `-m testapp` to `testapp/__main__.py`. On reload, `__main__` will be run as a script, preventing relative imports.

According to http://bugs.python.org/msg289874 it is now possible to [HIDDEN].

PS: Thanks for your awesome work on Tornado! :+1:
