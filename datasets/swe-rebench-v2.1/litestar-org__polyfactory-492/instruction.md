Enhancement: support Pydantic v1 and v2 at the same time
### Description

Pydantic v2 allows uses to use v1 models by importing them as `from pydantic.v1 import BaseModel`.
This however breaks polyfactory, which will switch behaviour depending on the version of the pydantic installed, not on the version of the model class. Ideally, it each class would be checked independently

### URL to code causing the issue

_No response_

### MCVE

```python
from pydantic.v1 import BaseModel
from polyfactory.factories.pydantic_factory import ModelFactory

class Duck(BaseModel):
    noise: str

class FakeDuckFactory(ModelFactory[Duck]):
    __model__ = Duck
```


produces

```
ConfigurationException: Model type Duck is not supported. To support it, register an appropriate base factory and subclass it for your factory.
```

### Release Version

2.12.0
