have request.get_json() return an error message
Request.get_json(), (or a new function), should return some sort of error message if the `force` parameter is not used notifying the user that this method only functions if the `mime` type is `application/json` unless the `force` option is used.

- in endpoint:
```
parsed_json = request.get_json() # Currently returns None
parsed_json.get("key") # Errors out
```

Alternatively, current usage can look like this:
```
parsed_json = request.get_json() # None
key_value = parsed_json.get("key", None)
if key_value:
    # do stuff
else:
    # do other stuff
```

In most scenarios there would be a failure at some stage or some form of custom handling for the current `None` behavior. Given that the function _expects_ that application/json is in use it seems reasonable to enforce that expectation at some level.

To be totally fair, this would be a breaking change to anyone relying on the current `None` behavior so it would also be great if some sort of `get_json_strict()` existed with similar functionality. The end goal here is to just have some default visibility around this particular behavior of `get_json()`.

This would affect https://github.com/pallets/werkzeug/blob/8292df2c464d9c4b13640f66fb7f393ef20a09a6/src/werkzeug/wrappers/request.py#L540

### Additional contract requirements

- The method is `Request.get_json(force=False, silent=False, cache=True)`.
- When the request `Content-Type` is not `application/json` and `silent` is `False`, `get_json()` raises `werkzeug.exceptions.BadRequest` (HTTP 400).
- When `silent` is `True`, an incorrect content type or a parsing failure returns `None`.
- `force=True` parses the body as JSON regardless of the request content type.
- On success, `get_json()` returns the parsed JSON object.
