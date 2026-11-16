Doesn't correctly validate when type is Enum
# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.5.1
            pydantic compiled: True
                 install path: /Users/<redacted>/.venvs/<redacted>/lib/python3.6/site-packages/pydantic
               python version: 3.6.5 (v3.6.5:f59c0932b4, Mar 28 2018, 03:03:55)  [GCC 4.2.1 (Apple Inc. build 5666) (dot 3)]
                     platform: Darwin-18.7.0-x86_64-i386-64bit
     optional deps. installed: []
```
Type validation works as expected when using children of Enums (e.g., [here](https://pydantic-docs.helpmanual.io/usage/types/#enums-and-choices)) but not when using Enums themselves.

```py
from enum import Enum

from pydantic import BaseModel


class FruitEnum(Enum):
    pear = 'pear'
    banana = 'banana'


class CookingModelA(BaseModel):
    fruit: FruitEnum


print(CookingModelA(fruit=FruitEnum.banana)) # works as expected


class CookingModelB(BaseModel):
    fruit: Enum


print(CookingModelB(fruit=FruitEnum.banana)) # fails validation with error
    """
    ValidationError: 1 validation error for CookingModelB
    fruit
      value is not a valid enumeration member; permitted:  (type=type_error.enum; enum_values=[])
    """
```
My expectation is that both should validate correctly, since `FruitEnum` is an instance of `Enum`.
