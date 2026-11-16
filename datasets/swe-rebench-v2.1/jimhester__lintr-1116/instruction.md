Allowing lone curly braces in some cases
I think the curly brace alone is the most readable in some cases. Particularly I came across this writing a `switch` where the default is multiline:

```
# file: brace.R
switch(x,
  "a" = do_something(x),
  "b" = do_another(x),
  { # default
    do_first(x)
    do_second(x)
  }
)
```

```
lintr::lint('brace.R')
/private/tmp/brace.R:4:3: style: Opening curly braces should never go on their own line and should always be followed by a new line.
  { # default
  ^
```

Is there any option to turn off this failure for this case? This alternative I think is not very readable:

```
switch(x,
  "a" = do_something(x),
  "b" = do_another(x), {
    do_first(x)
    do_second(x)
  }
)
```

There was also a request for exceptions in a case like `with` (though I would still use EOL-`{` in that case personally):

https://github.com/jimhester/lintr/issues/188#issuecomment-275643515

### Additional contract requirements

- A lone opening curly brace on its own line is allowed in the multiline `switch` default case shown above, and in a `with(...)` call.
