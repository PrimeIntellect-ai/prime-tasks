improve error message when passing a non-identifier to start a connection
we allow users to pass a connection variable to connect to a db. example:

```python
%load_ext sql

import duckdb
conn = duckdb.connect()

%sql conn
```

however, in some cases, the connection object might be part of a dictionary, list or object. examples:

```python
%sql object.property
%sql dictionary["key"]
%sql some_list[0]
```

Trying any of the above throws an error because our parser thinks it's SQL code. Instead, we should provide a more informative error:

```
"object.property" is not a valid connection identifier. Please pass the variable's name directly, as passing object attributes, dictionaries `some_dict[key]` or lists `some_list[0]` won't work. Example: `%sql connection`
```

so we need a way to identity such cases, we can use the following heuristics:

[HIDDEN]

if those conditions hold, then we can raise the error.

### Additional contract requirements

- The error must be raised as an `IPython.core.error.UsageError` (the raised
  exception's `error_type` attribute is `"UsageError"`).
- The error message must include the following text:

  ```
  '<argument>' is not a valid connection identifier. Please pass the variable's name directly, as passing object attributes, dictionaries or lists won't work.
  ```

  where `<argument>` is the offending argument exactly as passed to the magic
  (for example `conn_in_lst[0]`, `conn_in_dict['conn1']`, or `conn_in_obj.conn1`).
- When the magic receives exactly one whitespace-free argument that is valid Python syntax but is not a valid identifier, it must raise the invalid-connection-identifier error described above.
