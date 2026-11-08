Bad default value handling for Union
In #1522, I introduced the following bug, which broke the Pyface test suite:

```python
Python 3.9.7 (default, Sep  1 2021, 04:00:27)
[Clang 11.0.3 (clang-1103.0.32.62)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> from traits.api import *
>>> class A(HasTraits):
...     foo = Union(None, Int)
...
>>> class B(A):
...     foo = 5
...
>>> b = B()
>>> b.foo -= 1
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: unsupported operand type(s) for -=: '_Undefined' and 'int'
```
