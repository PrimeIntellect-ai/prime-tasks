Specifying validation=False on @input decorator omits schema from API spec
Specifying `validation=False` in the `@input` decorator results in no input schema documentation in the generated API spec. I think the goal of #573 is to allow for input documentation to be included in the API specification without validating the input; the input validation is being skipped, but the API specification doesn't include the input documentation as expected, so it's difficult for API clients to know what data needs to be passed in.

```python
from marshmallow import fields

from apiflask import APIFlask, Schema


app = APIFlask(__name__)

class TestSchema(Schema):
    field = fields.Str()

@app.post("/test_with_validation")
@app.input(TestSchema, validation=True)
def test_with_validation():
    return "Success!"

@app.post("/test_without_validation")
@app.input(TestSchema, validation=False)
def test_without_validation():
    return "Success!"

client = app.test_client()
result = client.get("/openapi.json")
assert "requestBody" in result.json["paths"]["/test_with_validation"]["post"]  # Passes
assert "requestBody" in result.json["paths"]["/test_without_validation"]["post"]  # Fails
```

Skipping input validation should still include input schema documentation in the API spec.

Environment:

- Python version: 3.11
- Flask version: 3.1.0
- APIFlask version: 2.3.0

### Additional contract requirements

- For `PATCH /pets_without_validation/{pet_id}` with `validation=False`, the generated `/openapi.json` document must set `paths['/pets_without_validation/{pet_id}']['patch']['requestBody']['content']['application/json']['schema']['$ref']` to `#/components/schemas/PetIn` and include `PetIn` in `components.schemas`.
