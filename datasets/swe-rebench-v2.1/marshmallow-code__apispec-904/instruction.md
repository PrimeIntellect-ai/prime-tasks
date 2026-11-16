Incorrect handling of marshmallow nested schema with allow_none=True in OpenAPI 3.1
If I define a marshmallow schema like this:
```python
from marshmallow import fields, Schema

class FooSchema(Schema):
    bar = fields.Integer(required=True)

class MySchema(Schema):
    foo = fields.Nested(FooSchema, allow_none=True)
```
it behaves as I intend - `MySchema` can load objects with a `foo` field that either matches `FooSchema` or is null, but `FooSchema` itself doesn't allow null values:
```python
>>> MySchema().loads('{"foo": {"bar": 1}}')
{'foo': {'bar': 1}}
>>> MySchema().loads('{"foo": null}')
{'foo': None}
>>> FooSchema().loads('null')
marshmallow.exceptions.ValidationError: {'_schema': ['Invalid input type.']}
```

But if I generate an API spec with this schema, using openapi version 3.1:
```python
from apispec import APISpec
from apispec.ext.marshmallow import MarshmallowPlugin

spec = APISpec(
    title="My API Spec",
    version="1.0.0",
    openapi_version="3.1.0",
    plugins=[MarshmallowPlugin()],
)
spec.components.schema("MySchema", schema=MySchema)
```
the resulting API spec is not equivalent to my marshmallow schema:
```python
>>> print(json.dumps(spec.to_dict()["components"]["schemas"], indent=2))
{
  "Foo": {
    "type": "object",
    "properties": {
      "bar": {
        "type": "integer"
      }
    },
    "required": [
      "bar"
    ]
  },
  "MySchema": {
    "type": "object",
    "properties": {
      "foo": {
        "type": [
          "null"
        ],
        "allOf": [
          {
            "$ref": "#/components/schemas/Foo"
          }
        ]
      }
    }
  }
}
```
This spec says that the value of `foo` _must_ be null, AND must be a `Foo` object, so in fact there is no valid input value here.

I think a correct spec in this instance should contain:
```
{
  "Foo": {
    "type": "object",
    "properties": {
      "bar": {
        "type": "integer"
      }
    },
    "required": [
      "bar"
    ]
  },
  "MySchema": {
    "type": "object",
    "properties": {
      "foo": {
        "anyOf": [
          {
            "$ref": "#/components/schemas/Foo"
          },
          {
            "type": "null"
          }
        ]
      }
    }
  }
}
```

I'm using apispec 6.3.0 and marshmallow 3.19.0
