Query parameter validation using Literal types in a dataclass fails
Query parameter validation fails to coerce valid data when using `Literal` in a dataclass:

```python
import json
from dataclasses import dataclass
from typing import Literal

from sanic import Sanic
from sanic.response import empty
from sanic_ext import validate


app = Sanic(name='name')


@dataclass
class Spec:
    name: Literal['foo', 'bar']


@app.get('/route')
@validate(query=Spec)
def route(_, body: Spec):
    print(body.name)
    return empty()


req, resp = app.test_client.get('/route', params={'name': 'baz'})
# ✔️ Validation catches invalid data:
# sanic_ext.exceptions.ValidationError: Invalid request body: Spec. Error: Value '['baz']' must be one of foo, bar

req, resp = app.test_client.get('/route', params={'name': 'bar'})
# ❌ Validation error coercing valid data:
# [ERROR] Exception occurred while handling uri: 'http://127.0.0.1:39541/route?name=bar'
# Traceback (most recent call last):
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/validators.py", line 25, in validate_body
#     return validator(model, body)
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/validators.py", line 38, in _validate_annotations
#     return check_data(model, body, schema, allow_multiple, allow_coerce)
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/check.py", line 147, in check_data
#     hydration_values[key] = hint.validate(
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/check.py", line 100, in validate
#     value = self.coerce(value)
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/check.py", line 109, in coerce
#     coerce_types = [arg for arg in args if not isinstance(None, arg)]
#   File ".../env/lib/python3.8/site-packages/sanic_ext/extras/validation/check.py", line 109, in <listcomp>
#     coerce_types = [arg for arg in args if not isinstance(None, arg)]
# TypeError: isinstance() arg 2 must be a type or tuple of types
# ...
# sanic_ext.exceptions.ValidationError: Invalid request body: Spec. Error: isinstance() arg 2 must be a type or tuple of types


```

**Expected behavior**
No error when valid query parameters are used.

**Environment (please complete the following information):**
Sanic v22.12.0, sanic-routing==22.8.0, sanic-testing==22.9.0, sanic-ext==22.12.0
