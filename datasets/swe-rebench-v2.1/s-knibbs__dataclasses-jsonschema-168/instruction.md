using Dict type in Python3.9 results AttributeError
The following code doesn't work in Python3.9:
```
from dataclasses import dataclass
from typing import Dict

from dataclasses_jsonschema import JsonSchemaMixin


@dataclass
class User(JsonSchemaMixin):
    stuffs: Dict


User.from_dict({'stuffs': {'a': 'b'}})
```
```
Traceback (most recent call last):
  File "<input>", line 1, in <module>
  File "<venvs>/lib/python3.9/site-packages/dataclasses_jsonschema/__init__.py", line 508, in from_dict
    cls._validate(data, validate_enums)
  File "<venvs>/lib/python3.9/site-packages/dataclasses_jsonschema/__init__.py", line 489, in _validate
    validate_func(data, cls.json_schema(validate_enums=validate_enums))
  File "<venvs>/lib/python3.9/site-packages/dataclasses_jsonschema/__init__.py", line 782, in json_schema
    properties[f.mapped_name], is_required = cls._get_field_schema(f.field, schema_options)
  File "<venvs>/lib/python3.9/site-packages/dataclasses_jsonschema/__init__.py", line 671, in _get_field_schema
    if field_type.__args__[1] is not Any:
  File "/usr/lib/python3.9/typing.py", line 694, in __getattr__
    raise AttributeError(attr)
AttributeError: __args__
```
Something must have changed around dataclasses because a Field's `.type` property no longer has `.__args__` for Dict, resulting the AttributeError above. This piece of code works well in Python3.8.
Python: 3.9.4
dataclasses-jsonschema: 2.14.1
It looks related: https://bugs.python.org/issue40397 (the `field_type` is no longer _GenericAlias (3.8) but _SpecialGenericAlias which no longer has the `.__args__`)
