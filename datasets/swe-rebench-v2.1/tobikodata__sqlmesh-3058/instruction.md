`Unable to create a loaded context` after bumping to 0.118.5
Hello there,

I am getting this error after upgrading to `0.118.5`.
The UI more specifically states `unable to created a loaded context`.


This is the full traceback:
```
Traceback (most recent call last):
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/bin/sqlmesh", line 8, in <module>
    sys.exit(cli())
             ^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/core.py", line 1078, in main
    rv = self.invoke(ctx)
         ^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/core.py", line 1685, in invoke
    super().invoke(ctx)
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/click/decorators.py", line 33, in new_func
    return f(get_current_context(), *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/cli/__init__.py", line 31, in wrapper
    return handler(sqlmesh_context, lambda: func(*args, **kwargs))
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/cli/__init__.py", line 40, in _default_exception_handler
    return func()
           ^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/cli/__init__.py", line 31, in <lambda>
    return handler(sqlmesh_context, lambda: func(*args, **kwargs))
                                            ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/cli/main.py", line 96, in cli
    context = Context(
              ^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/context.py", line 379, in __init__
    self.load()
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/context.py", line 511, in load
    project = self._loader.load(self, update_schemas)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/loader.py", line 128, in load
    models = self._load_models(
             ^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/loader.py", line 336, in _load_models
    models.update(self._load_python_models(macros, jinja_macros))
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/loader.py", line 423, in _load_python_models
    model = registry[name].model(
            ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/model/decorator.py", line 141, in model
    return create_python_model(
           ^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/model/definition.py", line 1931, in create_python_model
    _parse_dependencies(python_env, entrypoint) if python_env is not None else (set(), set())
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/core/model/definition.py", line 2228, in _parse_dependencies
    env = prepare_env(python_env)
          ^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/sotirisgkoulimaris/Documents/projects/dbol-elt/.venv/lib/python3.12/site-packages/sqlmesh/utils/metaprogramming.py", line 424, in prepare_env
    exec(executable.payload, env)
  File "<string>", line 1, in <module>
NameError: name 'func' is not defined
```
