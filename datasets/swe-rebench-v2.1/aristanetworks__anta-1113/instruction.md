bug(anta): TypeError: '<' not supported between instances of 'NoneType' and 'str'
The following error can occur if we try to sort a `ResultManager` by `custom_field` with results having `custom_field` set to `None`.
```
  File "/home/cbaillar/git_projects/anta/anta/result_manager/__init__.py", line 298, in sort
    self._result_entries.sort(key=lambda result: [getattr(result, field) for field in sort_by])
    ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: '<' not supported between instances of 'NoneType' and 'str'
```
I think something like `[HIDDEN]` could work.

### Additional contract requirements

- Sorting a `ResultManager` by `custom_field` must not raise `TypeError` when the results include both `None` and string values.
