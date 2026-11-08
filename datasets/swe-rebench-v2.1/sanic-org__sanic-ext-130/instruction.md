[Feature Request] Make pydantic models (or dicts) usable for openapi definition
**Is your feature request related to a problem? Please describe your use case.**
Pydantic models are not really usable for openapi definitions. It would be nice to use the models for validation and openapi.
The openapi decorator generates correct output for pydantic models in terms of properties and type, but nothing more. It would be nice to use pydantics `Field` for more details (example value, description, ...).
Pydantic is able to export a schema compatible to the openapi specs with `model.schema()`. This generates a dict, which means it would be enough to support dicts for the openapi definition.

**Describe the solution you'd like**
This should generate an openapi definition with an example field
```python
from sanic import Sanic, json
from sanic_ext import validate, openapi
from pydantic import BaseModel, Field

class Test(BaseModel):
    foo: str = Field(description="Foo Description", example="FOOO")
    bar: str = "test"


app = Sanic("test")

@app.get("/")
@openapi.definition(
    body={'application/json': Test.schema()},
)
@validate(json=Test)
async def get(request):
    return json({})
```

**Additional context**
-
