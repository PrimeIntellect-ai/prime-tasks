Support to add schemas to the OpenAPI spec explicitly
Sorry, the issue was submitted late

The specific problems are as follows

Like this doc, both RequestDTO and ResponseDTO will be displayed on the schema component of OpenAPI
```python
class A(MethodView):
    @input(RequestDTO, location="json")
    @output(ResponseDTO)
    def post(self, data):
        return {}
```
But not every schema is nested or explicitly used, such as checking data with marshmallow or dynamically specifying which schema to use, which cannot be displayed on the openapi.

Like this schema, it is dynamically loaded in the web app, but it wants to be displayed in the schema
```python
class S(Schema):
    f1 = fields.String()
    f2 = fields.String()
```

I hope there is a place to manually configure schema components in apiflask,TKS

### Additional contract requirements

- Setting the `SPEC_PROCESSOR_PASS_OBJECT` config to `True` makes the function registered with `app.spec_processor` receive an `apispec.APISpec` object as its `spec` argument instead of a dict.
- On that object, `spec.components.schema(name, schema=SomeSchema)` adds a schema component named `name` to the generated OpenAPI document, even when no route uses that schema.
- Schemas used by routes for request or response handling must still appear in the schema components of the generated document.
