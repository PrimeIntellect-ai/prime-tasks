[Bug] Dataclass optional not working in validate query
**Describe the bug**
I'm following this tutorial https://sanic.dev/en/plugins/sanic-ext/validation.html#implementation .
with define `dataclass` attribute with optional paramater,
 it will return 400 , if the query params `q` have value ex `q=123123`
 without value it will work without problem

 I also found the same issue when using `pydantic`

**Screenshots**
<img width="1290" alt="Screen Shot 2022-07-05 at 16 21 59" src="https://user-images.githubusercontent.com/7445136/177295868-db8253c4-6fb5-4cc2-90aa-2d82ab465b2e.png">


**To Reproduce**
```
from dataclasses import dataclass, asdict
from typing import Optional

from sanic import Sanic
from sanic.response import json
from sanic_ext import validate


app = Sanic("Sanic-APP")


@dataclass
class SearchParams:
    q: Optional[str] = None


@app.route("/")
@validate(query=SearchParams)
async def handler(request, query: SearchParams):
    return json(asdict(query))

```

**Expected behavior**
when the dataclass attribute is `Optional`, it should not error when we send the query params with value ex `?q=123456`

**Environment (please complete the following information):**
 - OS: Mac Catalina v10.15.7
 - Browser Chrome
 - Version 103.0.5060.53

### Additional contract requirements

The validation helpers below are public and are called with these signatures:

- `make_schema(agg, item)` in `sanic_ext.extras.validation.schema` takes an
  aggregate mapping as its first argument and a model class as its second
  argument, and returns the aggregate mapping populated with the model's field
  hints.
- `check_data(model_cls, data, schema, allow_multiple=False, allow_coerce=False)`
  in `sanic_ext.extras.validation.check` validates `data` against `schema` for
  `model_cls`, raising `TypeError` when `data` does not conform and returning
  silently otherwise.

A dataclass field declared `Optional[...]` (including `Optional[Union[...]]`
and PEP 604 `X | None`) must accept a supplied value of any of its allowed
types without error, and must accept `None`.

A dataclass field declared `Union[str, int]` (or `str | int`) must accept both
strings and integers and reject other types such as `float` and `None` with
`TypeError`.
