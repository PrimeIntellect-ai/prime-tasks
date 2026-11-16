`inserted` might be None
See https://github.com/Kinto/kinto/blob/a6b08389ebb441bee10f336fa03627eb3a8aa37f/kinto/core/storage/postgresql/__init__.py#L306-L308

If `inserted` becomes `None` you get a `TypeError` trying to call `inserted['inserted']`.

This has actually happened in a real production instance:

```
Exception(most recent call first)

TypeError: 'NoneType' object is not subscriptable
  File "kinto/core/utils.py", line 414, in follow_subrequest
    return request.invoke_subrequest(subrequest, **kwargs), subrequest
  File "pyramid/router.py", line 195, in invoke_subrequest
    return self.invoke_request(request, _use_tweens=use_tweens)
  File "pyramid/router.py", line 249, in invoke_request
    response = handle_request(request)
  File "pyramid/router.py", line 156, in handle_request
    view_name
  File "pyramid/view.py", line 642, in _call_view
    response = view_callable(context, request)
  File "pyramid/config/views.py", line 181, in __call__
    return view(context, request)
  File "pyramid/viewderivers.py", line 390, in attr_view
    return view(context, request)
  File "pyramid/viewderivers.py", line 368, in predicate_wrapper
    return view(context, request)
  File "pyramid/viewderivers.py", line 301, in secured_view
    return view(context, request)
  File "pyramid/viewderivers.py", line 439, in rendered_view
    result = view(context, request)
  File "pyramid/viewderivers.py", line 148, in _requestonly_view
    response = view(request)
  File "cornice/service.py", line 494, in wrapper
    response = view_()
  File "kinto/core/resource/__init__.py", line 468, in put
    record = self.model.create_record(new_record)
  File "kinto/core/resource/model.py", line 315, in create_record
    record = super().create_record(record, parent_id)
  File "kinto/core/resource/model.py", line 191, in create_record
    auth=self.auth)
  File "statsd/client.py", line 37, in _wrapped
    return_value = f(*args, **kwargs)
  File "kinto/core/storage/postgresql/__init__.py", line 308, in create
    if not inserted['inserted']:
```

For those with access see [this Sentry entry](https://sentry.prod.mozaws.net/operations/buildhub-prod/issues/3163658/).

### Additional contract requirements

- When storage creation receives no returned row from the database for the insert (the row is `None`), creating the record must not fail with a `TypeError`. It must raise `UnicityError` from `kinto.core.storage.exceptions`, the same error raised for any other conflicting record.
