better error when missing CTE
when using the `--with` argument, we access [here](https://github.com/ploomber/jupysql/blob/fcbf525be3b4e52225a9e3ecc0e08b9d324c96e9/src/sql/store.py#L42); however, if the passed key does not exist, the error traceback is pretty long (see attached notebook).

Instead, we should raise an UsageError:

```python
from IPython.core.error import UsageError

[HIDDEN]
```

To provide a more helpful message, we can also use [difflib](https://docs.python.org/3/library/difflib.html#difflib.get_close_matches) to check if there are any closes matches:

> "subsett"  is not a valid snippet identifier. Did you mean "subset"?

If there are no close matches, we can display all available keys:

> "subsett"  is not a valid snippet identifier. Valid identifiers are "one", "another", and "something"

### Additional contract requirements

When a non-empty snippet store does not contain a requested identifier, raise an IPython `UsageError` whose message identifies the requested identifier. If a valid identifier is a close match, the message must suggest at least one valid close match. If there is no close match, the message must make the available identifiers visible. The wording and formatting of these messages are not prescribed.
