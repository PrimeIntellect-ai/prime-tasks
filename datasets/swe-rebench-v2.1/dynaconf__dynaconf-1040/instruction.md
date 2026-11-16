[RFC] add `@get` converter
I need to add a new converter called `@get` to be used to simply call `settings.get` with specified key and use whatever value is there with the current type.

Example:

```python
from dynaconf import Dynaconf
settings = Dynaconf(settings_files=["a.py", "b.py"])

# a.py
THING = "value"

# b.py
ANOTHER_THING = "@get THING"
```

This is different than using `this` inside a lazy `@format/@jinja` because those 2 would cast to string by default or to specified combo like `@int @format {this[THING]}`.

The `@get` would just attempt to perform a `settings.get` and use whatever value is there, it will also allow a default to be specified.

```python
THING = "@get THING @int 789"
```

The above will translate to

```python
settings.get("THING", default="789", cast="@int")
```

Not sure if this must be lazily evaluated.


This feature will allow the fix of https://github.com/pulp/pulp_ansible/pull/1130

## Implementation


On [HIDDEN]


```python
[HIDDEN]
```

[HIDDEN]

### Additional contract requirements

- `DynaconfFormatError` is a public exception class that can be imported from
  the `dynaconf` package (`from dynaconf import DynaconfFormatError`) and is a
  subclass of `Exception`.
- `DynaconfFormatError` accepts an optional message string; when the message
  is omitted it defaults to an empty string.
- A malformed `@get` expression raises `DynaconfFormatError`, and the exception
  propagates to the caller.
- The `@get` expression accepts the forms `@get KEY`, `@get KEY @CAST`,
  `@get KEY DEFAULT` and `@get KEY @CAST DEFAULT`, where `KEY` is the name of
  the setting to look up, `@CAST` is an optional cast marker such as `@int` or
  `@float`, and `DEFAULT` is an optional fallback value used when `KEY` is not
  defined.
- Without a cast marker, `@get` preserves the referenced setting's current
  value and type. When a cast marker is supplied, it is applied to the
  referenced value if defined, or to the fallback value if the setting is
  undefined.
