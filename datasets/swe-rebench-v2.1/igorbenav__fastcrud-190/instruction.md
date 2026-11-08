Missing type parsing to dynamic filter
**Describe the bug or question**
I have a type issue with the filter created from FilterConfig. The filter does not convert the query param before querying the database.


**To Reproduce**
Configure a filter with a UUID that is not a primary key


**Description**
I noticed that the function _create_dynamic_filters from fastcrud/endpoint/helper.py take column_types has parameter but never use it.
When I try to work with UUID object I got error because the id I pass in the query param of the request is always a string and is never parsed as an object.
I was able to resolve my problem with the following code (which is the filter function from _create_dynamic_filters function):
```python
def filters(
        **kwargs: Any,
    ) -> dict[str, Any]:
        filtered_params = {}
        for key, value in kwargs.items():
            if value is not None:
                [HIDDEN]
        return filtered_params
```

### Additional contract requirements

- `FilterConfig` is importable from the top-level package as `from fastcrud import FilterConfig`. It accepts arbitrary keyword arguments, each naming a filter field (for example `FilterConfig(uuid_field=None, int_field=None)`); every field is optional and may be omitted.
- `_create_dynamic_filters` is importable from `fastcrud.endpoint.helper` as `from fastcrud.endpoint.helper import _create_dynamic_filters`.
- The callable returned by `_create_dynamic_filters(filter_config, column_types)` accepts arbitrary keyword arguments and returns a dictionary. For each argument whose value is not `None`, if `column_types` maps that argument name to a callable, the value is converted by calling that callable; if the call raises `ValueError` or `TypeError`, the original value is kept instead. Arguments whose value is `None` are omitted from the result, and arguments with no mapped callable are kept unchanged.
- `_create_dynamic_filters(None, {})` returns a callable that returns `{}` when called with no arguments.
