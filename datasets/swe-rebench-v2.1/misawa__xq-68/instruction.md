Cannot use null and booleans in object value
I noticed that I can't use some values in in object value.
```sh
❯ xq -n '{x: null}'
Error: compile query

Caused by:
    CompileError(UnknownFunction(Identifier("null"), 0))

❯ xq -n '{x: true}'
Error: compile query

Caused by:
    CompileError(UnknownFunction(Identifier("true"), 0))

❯ xq -n '{x: false}'
Error: compile query

Caused by:
    CompileError(UnknownFunction(Identifier("false"), 0))

❯ xq --version
xq 0.2.3-a7d4cfbf962f3570b326dd97ecf288365d396ed4
```
