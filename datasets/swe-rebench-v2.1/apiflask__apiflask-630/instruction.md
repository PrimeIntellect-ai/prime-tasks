Specifying `validation=False` on `@input` decorator yields unexpected input when endpoint accepts a list
For endpoints that accept in a list of values in their input, specifying `validation=False` on the `@input` decorator yields an empty dictionary when an empty list is passed in to the endpoint. This is a change in behaviour compared to when the `validation` argument is omitted, in which case an empty list is passed along to the application code.

```python
from marshmallow import fields

from apiflask import APIFlask, Schema

app = APIFlask(__name__)


class TestSchema(Schema):
    field = fields.Str(required=True)


@app.post("/test_with_validation")
@app.input(TestSchema(many=True), validation=True)
def test_with_validation(json_data):
    return json_data


@app.post("/test_without_validation")
@app.input(TestSchema(many=True), validation=False)
def test_without_validation(json_data):
    return json_data


client = app.test_client()
payload = [{'data': 'value'}]
result = client.post("/test_with_validation", json=payload)
assert result.status_code == 422  # Input validation fails
result = client.post("/test_without_validation", json=payload)
assert result.status_code == 200
assert result.json == payload

payload = []
result = client.post("/test_with_validation", json=payload)
assert result.status_code == 200
assert result.json == payload
result = client.post("/test_without_validation", json=payload)
assert result.status_code == 200
assert result.json == payload  # Fails; result is {} instead of []
```

The output from the `@input` decorator shouldn't be impacted by skipping validation (i.e., the raw input should be passed along, and not interfered with).

Environment:

- Python version: 3.11
- Flask version: 3.1.0
- APIFlask version: 2.3.1
