Trailing blanks in envvars of boolean options cause otherwise valid values to be rejected
### Actual Behavior

When defining a boolean option that also can be set via envvar, trailing blanks in the envvar value cause otherwise valid values to be rejected with this error message:

```
Error: Invalid value for '--something': true  is not a valid boolean
```
Because the value is shown in the error message unquoted, the trailing blank cannot easily be seen, but it is there.

Why is this an issue?

Invoking the command on Linux/macOS as follows does not trigger the issue:
```
$ SOMETHING=true command
```

However, invoking it like this on Windows does trigger the issue:
```
> set SOMETHING=true & command
```

Apparently, Windows sets the envvar with a trailing blank in this case.

The issue can be circumvented like this:
```
> set SOMETHING=true& command
```

Here is the code that causes this behavior:

click/types.py at line 406:
```
class BoolParamType(ParamType):
    name = "boolean"

    def convert(self, value, param, ctx):
        if isinstance(value, bool):
            return bool(value)
        [HIDDEN]
        if value in ("true", "t", "1", "yes", "y"):
            return True
        elif value in ("false", "f", "0", "no", "n"):
            return False
        self.fail("{!r} is not a valid boolean".format(value), param, ctx)

    def __repr__(self):
        return "BOOL"
```
### Expected Behavior

I would like to see click strip any leading or trailing blanks from the boolean envvar before it is evaluated.

### Environment

* Python version: any
* Click version: 7.1.2
