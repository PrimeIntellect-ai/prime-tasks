Docs: How to handle Callable types
### Summary

Python version: 3.13
Polyfactory: 2.19.0
Pydantic: 2.10.6

Given the following:
```
MyTypedFunc = Callable[
    [str],
    Coroutine[Any, Any, AsyncIterable],
]


class TestClass(BaseModel):
    name: str
    my_function: MyTypedFunc


class TestClassFactory(ModelFactory[TestClass]):
    __model__ = TestClass


def test_test_class() -> None:
    iut = TestClassFactory.build()

    assert isinstance(iut, TestClass)
```
When run in pytest, I get the following error at the `build()` statement:
```
>   return tuple(TYPE_MAPPING.get(arg, arg) for arg in get_args(self.annotation))
E   TypeError: unhashable type: 'list'
```
I have tried mocking the function and ignoring the field.  It isn't clear in the documentation how to handle this scenario, and, for all it's praise, AI, hasn't been any help at all.

Is there a way to handle this?

### Additional contract requirements

Building a model that has a `Callable`-annotated field must not raise an internal
`TypeError` (such as `TypeError: unhashable type: 'list'`). Instead, the factory must
raise a `polyfactory.exceptions.ParameterException` whose message indicates that the
type is unsupported; the message contains the text `Unsupported type:`.
