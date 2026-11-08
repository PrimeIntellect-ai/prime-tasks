[ADAP-500] [Bug] dbt-redshift 1.5 does not work with non-standard redshift hostnames
### Is this a new bug in dbt-redshift?

- [X] I believe this is a new bug in dbt-redshift
- [X] I have searched the existing issues, and I could not find an existing issue for this bug

### Current Behavior

When upgrading to dbt 1.5, I get an 'index out of range error' when attempting to use things that connect to the database.

This is related to using a non-standard hostname for redshift - in my case I am opening a SSH tunnel to Redshift and using localhost as the host.

### Expected Behavior

It works with the same configuration as prior versions of DBT or allows a region configuration to side-step this issue.

### Steps To Reproduce

1. Start a SSH tunnel to redshift (the bug would also manifest if you have a cname to a redshift cluster) and localhost or the cname for the 'host' in your `profiles.yml`.
2. Attempt to run a model or do something that connects to redshift

### Relevant log output

```shell
❯ dbt compile
19:37:05  Running with dbt=1.5.0
19:37:05  Found 111 models, 356 tests, 6 snapshots, 0 analyses, 746 macros, 0 operations, 1 seed file, 135 sources, 0 exposures, 0 metrics, 0 groups
19:37:05
19:37:05  Encountered an error:
list index out of range
19:37:05  Traceback (most recent call last):
  [HIDDEN]
              ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^
IndexError: list index out of range

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/redshift/connections.py", line 190, in exception_handler
    yield
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/base/impl.py", line 1043, in execute_macro
    result = macro_function(**kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 330, in __call__
    return self.call_macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 257, in call_macro
    return macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 763, in __call__
    return self._invoke(arguments, autoescape)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 777, in _invoke
    rv = self._func(*arguments)
         ^^^^^^^^^^^^^^^^^^^^^^
  File "<template>", line 21, in macro
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/sandbox.py", line 393, in call
    return __context.call(__obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 298, in call
    return __obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 330, in __call__
    return self.call_macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 257, in call_macro
    return macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 763, in __call__
    return self._invoke(arguments, autoescape)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 777, in _invoke
    rv = self._func(*arguments)
         ^^^^^^^^^^^^^^^^^^^^^^
  File "<template>", line 21, in macro
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/sandbox.py", line 393, in call
    return __context.call(__obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 298, in call
    return __obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 330, in __call__
    return self.call_macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 257, in call_macro
    return macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 763, in __call__
    return self._invoke(arguments, autoescape)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 777, in _invoke
    rv = self._func(*arguments)
         ^^^^^^^^^^^^^^^^^^^^^^
  File "<template>", line 39, in macro
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/sandbox.py", line 393, in call
    return __context.call(__obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 298, in call
    return __obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 330, in __call__
    return self.call_macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/clients/jinja.py", line 257, in call_macro
    return macro(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 763, in __call__
    return self._invoke(arguments, autoescape)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 777, in _invoke
    rv = self._func(*arguments)
         ^^^^^^^^^^^^^^^^^^^^^^
  File "<template>", line 52, in macro
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/sandbox.py", line 393, in call
    return __context.call(__obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/jinja2/runtime.py", line 298, in call
    return __obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/base/impl.py", line 289, in execute
    return self.connections.execute(sql=sql, auto_begin=auto_begin, fetch=fetch)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/redshift/connections.py", line 259, in execute
    _, cursor = self.add_query(sql, auto_begin)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/redshift/connections.py", line 284, in add_query
    connection, cursor = super().add_query(
                         ^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/sql/connections.py", line 58, in add_query
    self.begin()
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/sql/connections.py", line 170, in begin
    self.add_begin_query()
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/sql/connections.py", line 153, in add_begin_query
    return self.add_query("BEGIN", auto_begin=False)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
              ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^
IndexError: list index out of range

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 86, in wrapper
    result, success = func(*args, **kwargs)
                      ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 71, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 142, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 168, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 215, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/requires.py", line 250, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/cli/main.py", line 346, in compile
    results = task.run()
              ^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/task/runnable.py", line 441, in run
    result = self.execute_with_hooks(selected_uids)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/task/runnable.py", line 403, in execute_with_hooks
    self.before_run(adapter, selected_uids)
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/task/runnable.py", line 390, in before_run
    self.populate_adapter_cache(adapter)
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/task/runnable.py", line 381, in populate_adapter_cache
    adapter.set_relations_cache(self.manifest)
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/base/impl.py", line 461, in set_relations_cache
    self._relations_cache_for_schemas(manifest, required_schemas)
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/redshift/impl.py", line 150, in _relations_cache_for_schemas
    super()._relations_cache_for_schemas(manifest, cache_schemas)
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/base/impl.py", line 438, in _relations_cache_for_schemas
    for relation in future.result():
                    ^^^^^^^^^^^^^^^
  File "/Users/alexkoch/.asdf/installs/python/3.11.2/lib/python3.11/concurrent/futures/_base.py", line 449, in result
    return self.__get_result()
           ^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/.asdf/installs/python/3.11.2/lib/python3.11/concurrent/futures/_base.py", line 401, in __get_result
    raise self._exception
  File "/Users/alexkoch/.asdf/installs/python/3.11.2/lib/python3.11/concurrent/futures/thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/utils.py", line 464, in connected
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/alexkoch/Library/Caches/pypoetry/virtualenvs/espark-dbt-7mBGFPKz-py3.11/lib/python3.11/site-packages/dbt/adapters/sql/impl.py", line 180, in list_relations_without_caching
    results = self.execute_macro(LIST_RELATIONS_MACRO_NAME, kwargs=kwargs)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
              ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^
IndexError: list index out of range
```


### Environment

```markdown
- OS: ubuntu 20.04, OSX 13.3.1
- Python: 3.11.2
- dbt-core: 1.5.0
- dbt-redshift: 1.5.0
```


### Additional Context

The adapter is hard-coded to parse the region from the host value.

https://github.com/dbt-labs/dbt-redshift/blob/aa98c958981fe112079e55b5831daf32b45b39f4/dbt/adapters/redshift/connections.py#L102

### Additional contract requirements

- A Redshift profile may provide an explicit region using the `region` credential field. When supplied, that region must allow connections to work with hostnames that do not encode a parseable AWS region.
