Crash postgresql backend: TypeError: argument of type 'int' is not iterable
Apparently happens with `?like_target.version=65`

This works: https://buildhub.prod.mozaws.net/v1/buckets/build-hub/collections/releases/records?_limit=1&like_target.version=%2265%22

This crashes: https://buildhub.prod.mozaws.net/v1/buckets/build-hub/collections/releases/records?_limit=1&like_target.version=65

```
TypeError: argument of type 'int' is not iterable
(12 additional frame(s) were not displayed)
...
  File "kinto/core/resource/__init__.py", line 292, in collection_get
    include_deleted=include_deleted)
  File "kinto/core/resource/model.py", line 100, in get_records
    auth=self.auth)
  File "statsd/client.py", line 37, in _wrapped
    return_value = f(*args, **kwargs)
  File "kinto/core/storage/postgresql/__init__.py", line 634, in get_all
    modified_field)
  File "kinto/core/storage/postgresql/__init__.py", line 741, in _format_conditions
    if '*' not in value
```

A like query with a value that is not a string should return 400

Like it is done here:
https://github.com/Kinto/kinto/blob/ea5f66dd4441447292ce26a068bdb690b7de7496/kinto/core/resource/__init__.py#L1004-L1011

https://sentry.prod.mozaws.net/operations/buildhub-prod/issues/4990222/
