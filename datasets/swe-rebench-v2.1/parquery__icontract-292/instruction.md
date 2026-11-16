Feature request: immediate invariant evaluation.
Hi,

Very much taken by your library's functionality: much appreciated!

I would like to request an (perhaps optional?) feature for immediate evaluation of invariants (optional because, no doubt, this incurs a runtime penalty).

At the moment, as per [the documentation](https://icontract.readthedocs.io/en/latest/usage.html#invariants), invariants are evaluated when an object's method is called...
```python
from dataclasses import dataclass
import icontract

@icontract.invariant(lambda self: self.bar >= 0)
@dataclass
class Foo():
    bar:int = 0
    def invoke(self): pass

obj = Foo(bar=0)
obj.bar = -10   # <- Violates the contract.
obj.invoke()    # <- Contract evaluation.
```

...yielding the following (expected) exception:

```
.venvuser@localhost:~/home/user/test$ python3 test.py
Traceback (most recent call last):
  File "/home/user/test/test.py", line 12, in <module>
    obj.invoke()    # <- Contract evaluation.
    ^^^^^^^^^^^^
  File "/home/user/test/.venv/lib/python3.12/site-packages/icontract/_checkers.py", line 1133, in wrapper
    _assert_invariant(contract=contract, instance=instance)
  File "/home/user/test/.venv/lib/python3.12/site-packages/icontract/_checkers.py", line 530, in _assert_invariant
    raise _create_violation_error(
icontract.errors.ViolationError: File /home/user/test/test.py, line 4 in <module>:
self.bar >= 0:
self was Foo(bar=-10)
self.bar was -10
```

In comparison, the [Deal](https://pypi.org/project/deal/) package immediately evaluates the contract...
```python
from dataclasses import dataclass
import deal

@deal.inv(lambda self: self.bar >= 0)
@dataclass
class Foo():
    bar:int = 0
    def invoke(self): pass

obj = Foo(bar=0)
#print(f"obj type={type(obj)}")
obj.bar = -10   # <- Violates the contract, contract evaluation.
```

...yielding the following (expected) exception:
```
.venvuser@localhost:~/home/user/test$ python3 test.py
Traceback (most recent call last):
  File "/home/user/test/test.py", line 14, in <module>
    obj.bar = -10   # <- Violates the contract, contract evaluation.
    ^^^^^^^
deal.InvContractError: expected self.bar >= 0
```

Likewise, [Pydantic](https://pypi.org/project/pydantic/) can be persuaded (with the [validate_assignment](https://docs.pydantic.dev/latest/api/config/#pydantic.config.ConfigDict.validate_assignment) [configuration](https://docs.pydantic.dev/latest/api/config/#pydantic.config.ConfigDict) option) to immediate type hint evaluation...
```python
from pydantic.dataclasses import dataclass
from pydantic import ConfigDict

@dataclass(config=dict(validate_assignment=True))
class Foo():
    bar:int = 0
    def invoke(self): pass

obj = Foo(bar=0)
obj.bar = 'bar' # <- Violates type hint, type evaluation.
```

...yielding the following (expected) exception:
```
.venvuser@localhost:~/test$ python3 test.py
Traceback (most recent call last):
  File "/home/user/test/test.py", line 12, in <module>
    obj.bar = 'bar' # <- Violates type hint, type evaluation.
    ^^^^^^^
  File "/home/user/test/.venv/lib/python3.12/site-packages/pydantic/_internal/_dataclasses.py", line 189, in validated_setattr
    validator.validate_assignment(instance, field, value)
pydantic_core._pydantic_core.ValidationError: 1 validation error for Foo
bar
  Input should be a valid integer, unable to parse string as an integer [type=int_parsing, input_value='bar', input_type=str]
    For further information visit https://errors.pydantic.dev/2.7/v/int_parsing
```

Such added functionality would pursue me to use your library instead of Pydantic (which requires subclassing [BaseModel](https://docs.pydantic.dev/latest/api/base_model/) and either more convoluted [model](https://docs.pydantic.dev/latest/api/base_model/#pydantic.BaseModel.model_validate) or [Annotated](https://docs.pydantic.dev/latest/concepts/validators/) validation) or Deal (which performs, in my opinion, undesirable runtime subclassing):
```
obj type=<class 'deal._runtime._invariant.FooInvarianted'>
```

In the solution sphere (without knowing the internals of your code) perhaps [descriptor](https://docs.python.org/3/howto/descriptor.html#validator-class)s or [object-tracker](https://pypi.org/project/object-tracker/) could assist with such functionality?

### Additional contract requirements

The feature is exposed through the following public names.

- Add a public enum `icontract.InvariantCheckEvent` that is a subclass of `enum.Flag`.
  It has the members `CALL`, `SETATTR` and `ALL`, where `ALL` is the combination
  `CALL | SETATTR`. The members can be combined with the bitwise or operator `|`.
- Add a keyword argument `check_on` to the public decorator `icontract.invariant`.
  Its value is an `InvariantCheckEvent` and its default is `InvariantCheckEvent.CALL`.
  It selects when the invariant is evaluated:
  - `InvariantCheckEvent.CALL` evaluates the invariant before and after each method call
    (the default behaviour).
  - `InvariantCheckEvent.SETATTR` evaluates the invariant before and after each
    attribute assignment (`__setattr__`).
  - `InvariantCheckEvent.ALL` evaluates the invariant on both method calls and
    attribute assignments.
