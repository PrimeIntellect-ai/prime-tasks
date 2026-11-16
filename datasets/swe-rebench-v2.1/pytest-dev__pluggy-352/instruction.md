Remove manual kwargs-only check?
A little trivial issue.

The hookcaller `__call__` (e.g. `pm.hook.myhook(...)`) requires keyword-only arguments. This is currently checked manually:

https://github.com/pytest-dev/pluggy/blob/172ca9f59e8f1029ec734647b38ce4e2c4d7dba2/src/pluggy/_hooks.py#L384-L386

and provides a nice exception message (though it could be nicer...).

[HIDDEN]

```py
    [HIDDEN]
```

[HIDDEN] This provides a worse exception message: `_HookCaller.__call__() takes 1 positional argument but 2 were given` (it's still possible to find the line which has the problem from the stacktrace).

On the other hand, [HIDDEN] has the better typing (i.e. mypy will be able to catch bad usages), and removes the slight overhead of the check (likely not significant though).

I'm inclined to make the change but wonder if others agree.

### Additional contract requirements

- Hook callers continue to accept keyword arguments and reject positional arguments with TypeError.
- A hook caller's inspectable signature must expose no positional-accepting parameters.
