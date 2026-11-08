support for built-in `dataclass` breaks pickle
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: True
                 install path: /Users/aimestereo/.pyenv/versions/3.7.6/envs/feed/lib/python3.7/site-packages/pydantic
               python version: 3.7.6 (default, Jan 30 2020, 16:07:03)  [Clang 11.0.0 (clang-1100.0.33.17)]
                     platform: Darwin-19.6.0-x86_64-i386-64bit
     optional deps. installed: ['typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

thanks to @PrettyWood 1.7 Introduced cool [support of built-in dataclass](https://github.com/samuelcolvin/pydantic/pull/1817). But in our project this broke pickle

```py
import pickle
import dataclasses

import pydantic


@dataclasses.dataclass
class BuiltInDataclass:
    value: int


class PydanticModel(pydantic.BaseModel):
    built_in_dataclass: BuiltInDataclass


print(pickle.dumps(
    PydanticModel(built_in_dataclass=BuiltInDataclass(value=0))
))
```

output:
```
---------------------------------------------------------------------------
PicklingError                             Traceback (most recent call last)
<ipython-input-14-7d67a44cf353> in <module>
     15
     16 print(pickle.dumps(
---> 17     PydanticModel(built_in_dataclass=BuiltInDataclass(value=0))
     18 ))

PicklingError: Can't pickle <class '__main__.BuiltInDataclass'>: it's not the same object as __main__.BuiltInDataclass
```

---

For better understanding here's an issue of pickle outside of pydantic context. This is an old pickle problem, when different classes have the same name, simple way to reproduce:
```
import pickle


class A: pass


# this is an analogy of how pydantic convert built-in dataclass
B = type(A.__name__, (A,), {})


print(A)
# <class '__main__.A'>

print(B)
# <class '__main__.A'>

pickle.dumps(A)
# b'\x80\x03c__main__\nA\nq\x00.'

pickle.dumps(B)
# error
```
output
```
---------------------------------------------------------------------------
PicklingError                             Traceback (most recent call last)
<ipython-input-2-b97d2c67736c> in <module>
     10
     11 print(pickle.dumps(A))
---> 12 print(pickle.dumps(B))

PicklingError: Can't pickle <class '__main__.A'>: it's not the same object as __main__.A
```

---

As a result we can't use this feature, we're stick to intermediate classes that converts buit-in dataclasses to pydantic:

```
class SerializedDataclass(pydantic.BaseModel):
	# copy/paste of all fields from built-in dataclass
    value: float

```

### Additional contract requirements

When a built-in `dataclasses.dataclass` is used as a field type in a Pydantic model, the class of that field's value must itself be picklable: pickling that class and unpickling it must yield the same class object. Two distinct built-in dataclasses that share the same name must each remain independently picklable.
- When assigning an invalid value to the wrapped dataclass's `value` field with assignment validation enabled, raise `ValidationError` with a message matching `value\n +value is not a valid integer`.
