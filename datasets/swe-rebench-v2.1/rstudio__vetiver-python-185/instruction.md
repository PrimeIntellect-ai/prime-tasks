pydantic v2.0 breaking prototypes
Pydantic's V2.0 will break prototype creation in vetiver.

To reproduce error:

1. Update to Pydantic V2.0 (compatible FastAPI release is not out yet, you must `pip install --pre --upgrade fastapi pydantic`).
2. Run:
```python
from vetiver import mock, VetiverModel, VetiverAPI

X, y = mock.get_mock_data()
model = mock.get_mock_model().fit(X, y)
v = VetiverModel(
    model=model,
    prototype_data=X,
    model_name="my_model",
    versioned=None,
    description="A regression model for testing purposes",
)
```

Output:

```python
PydanticUserError: A non-annotated attribute was detected: `B = {0: 22, ... 99: 84}`.
All model fields require a type annotation; if `B` is not meant to be a field, you may
be able to resolve this error by annotating it as a `ClassVar` or updating
`model_config['ignored_types']`.

For further information visit https://errors.pydantic.dev/2.0/u/model-field-missing-annotation
```

This is happening at the dynamic creation of prototypes using `pydantic.create_model()`

### Additional contract requirements

- For an array prototype, `prototype.construct().__dict__` must equal `{"0": 96, "1": 11, "2": 33}`.
