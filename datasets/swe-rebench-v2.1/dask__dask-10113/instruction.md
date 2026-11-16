Removal of dask.compatibility.entry_points has broken dask-kubernetes
It looks like `dask.compatibility.entry_points` was removed in #10070 without warning. This was being used in `dask-kubernetes` so CI is now failing.

https://github.com/dask/dask-kubernetes/actions/runs/4499027159/jobs/7916366189?pr=683

cc @graingert @jrbourbeau

### Additional contract requirements

- Restore `dask.compatibility.entry_points(group=None)` as a compatibility API. It must accept the optional `group` keyword and return entry points belonging to that group when one is provided; when omitted, it returns entry points across all groups.
- Calling this compatibility API emits a `DeprecationWarning` advising users to migrate to `importlib_metadata.entry_points`.
