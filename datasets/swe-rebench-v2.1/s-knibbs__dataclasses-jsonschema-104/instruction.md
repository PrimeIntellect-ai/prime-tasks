don't allow undeclared object properties
Thanks for the great work on this project, been really useful thus far.

We used `"additionalProperties": false` for objects in our (hand-written) json-schema's, which was helpful to prevent invalid inputs. In this project I see no way of achieving the same.

```python
from dataclasses import dataclass
from dataclasses_jsonschema import JsonSchemaMixin

@dataclass
class Point(JsonSchemaMixin):
    "A 2D point"
    x: float
    y: float

# adding an additional key to the dict results in the key being dropped
print(Point.from_dict({"x": 1.1, "y": 2.2, "z": 3.3}))
Point(x=1.1, y=2.2)
```

This is especially problematic with items that have defaults, if a field name is typod validation will still pass, but the resulting object will have unexpected values.

[HIDDEN]

```python
Point.from_dict({"x": 1.1, "y": 2.2, "z": 3.3})
Traceback (most recent call last):
  File "/Users/jmmccon/.pyenv/versions/taskcat-v9-3.6.9/lib/python3.6/site-packages/dataclasses_jsonschema/__init__.py", line 421, in _validate
    validate_func(data, cls.json_schema())
  File "/Users/jmmccon/.pyenv/versions/taskcat-v9-3.6.9/lib/python3.6/site-packages/jsonschema/validators.py", line 899, in validate
    raise error
jsonschema.exceptions.ValidationError: Additional properties are not allowed ('z' was unexpected)
```

I'm happy to pr a change, but not sure if I've missed some way to do this that is already catered for, or even if others want this behavior (One thought to make it optional is to provide an additional mixin `StrictJsonSchemaMixin` that adds this)

### Additional contract requirements

A dataclass may opt into rejecting undeclared object properties by passing `allow_additional_props=False` in its `JsonSchemaMixin` class declaration. In this mode, converting a mapping with an undeclared property through `from_dict` must raise `ValidationError`. The default mode remains permissive about undeclared properties. In strict mode, the generated object JSON Schema must disallow additional properties.
