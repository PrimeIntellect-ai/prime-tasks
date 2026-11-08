Validators do not raise IndexError when it catches a ValueError
Hi. When a validator accidentally raises a ZeroDivisionError, the is correctly raised, but when a validator accidentally raises a ValueError, an IndexError is raised instead. This makes the debugging a bit more difficult.

Here is a script to reproduce the problem:

```python
import wtforms
import werkzeug


def division_error_validator(form, field): raise ZeroDivisionError
class DivisionErrorForm(wtforms.Form):
    foo = wtforms.StringField(validators=[division_error_validator])

def value_error_validator(form, field): raise ValueError
class ValueErrorForm(wtforms.Form):
    foo = wtforms.StringField(validators=[value_error_validator])


try:
    DivisionErrorForm(werkzeug.ImmutableMultiDict({"bar": "baz"})).validate()
except ZeroDivisionError:
    print("ZeroDivisionError OK")
except Exception as exc:
    print("ZeroDivisionError KO - found %s" % type(exc))

try:
    ValueErrorForm(werkzeug.ImmutableMultiDict({"bar": "baz"})).validate()
except ValueError:
    print("ValueError OK")
except Exception as exc:
    print("ValueError KO - found %s" % type(exc))

# prints
# ZeroDivisionError OK
# ValueError KO - found <type 'exceptions.IndexError'>
```
