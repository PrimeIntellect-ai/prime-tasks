Override place holder for mapper
I have a mapper that takes a json file path and unmarshals it into the arguments with `type:"jsonfile"`.  Right now the help text says

```
--myflag=KEY=VALUE;...
```

but ideally it would say `--myflag=PATH` or something.  It always takes a path so `KEY=VALUE` could be confusing.

Is there a way to have the mapper override the help text here, or could that functionality be added?

### Additional contract requirements

- A mapper may provide a `PlaceHolder(*kong.Flag) string` method. Help output must use its returned string as the flag’s value placeholder instead of the type-derived default.
