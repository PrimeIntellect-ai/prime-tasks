Bug: Pydantic Json type is disregarded when creating mock data
### Description

It seems like the pydantic_factory completely disregards a given [Json](https://docs.pydantic.dev/latest/usage/types/json/) type for a field if it has any nesting.

I ran into the problem today while trying to create test with a more nested model, but realized it's reproduceable with the simplest of examples.

[HIDDEN]

I contemplated trying to fix it but at least for now I don't really know how to proceed.

### MCVE

```python
from pydantic import BaseModel, Json
from polyfactory.factories.pydantic_factory import ModelFactory

class BasicTestModel(BaseModel):
    body: Json[int]


class BasicTestFactory(ModelFactory):
    __model__ = BasicTestModel


basicTest = BasicTestFactory.build()
```


### Steps to reproduce

```bash
1. Create a Model with a Json field.
2. Create a Factory for the model.
3. Try to build a mock model with the factory.
```

### Logs

```bash
Traceback (most recent call last):
  File ".../polyfactory-json/test.py", line 40, in <module>
    basicTest = BasicTestFactory.build()
                ^^^^^^^^^^^^^^^^^^^^^^^^
  File ".../polyfactory/factories/pydantic_factory.py", line 310, in build
    return cls.__model__(**processed_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File ".../pydantic/main.py", line 150, in __init__
    __pydantic_self__.__pydantic_validator__.validate_python(data, self_instance=__pydantic_self__)
pydantic_core._pydantic_core.ValidationError: 1 validation error for BasicTestModel
body
  JSON input should be string, bytes or bytearray [type=json_type, input_value=6014, input_type=int]
    For further information visit https://errors.pydantic.dev/2.1.2/v/json_type
```


### Litestar Version

-

### Platform

- [X] Linux
- [X] Mac
- [ ] Windows
- [ ] Other (Please specify in the description above)

### Additional contract requirements

- Building a model with a Pydantic `Json[T]` field must produce a successfully validated model whose field value conforms to `T`, including when `T` is a nested model.
