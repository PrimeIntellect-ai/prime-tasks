deprecating legacy plot API
once https://github.com/ploomber/jupysql/pull/508 is merged, we should start showing deprecation warnings:

https://github.com/ploomber/jupysql/blob/8ce3334182733145dbea6ece9e3d59e30237788c/src/sql/run.py#L232
https://github.com/ploomber/jupysql/blob/8ce3334182733145dbea6ece9e3d59e30237788c/src/sql/run.py#L302

and tell people they should use the `%sqlplot` API

### Additional contract requirements

- Calling `ResultSet.pie()` must emit exactly one warning with the message `.pie() is deprecated and will be removed in a future version. Use %sqlplot pie instead. For more help, find us at https://ploomber.io/community ` (including the final space). Calling `ResultSet.bar()` must emit exactly one warning with the message `.bar() is deprecated and will be removed in a future version. Use %sqlplot bar instead. For more help, find us at https://ploomber.io/community ` (including the final space). Calling `ResultSet.plot()` must emit exactly one warning with the message `.plot() is deprecated and will be removed in a future version. For more help, find us at https://ploomber.io/community ` (including the final space).
