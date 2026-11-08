LocalProxy breaking isinstance() for abc.ABC
When tested with isinstance() against an ABC, LocalProxy instances raise an exception rather than returning False.

```
import abc
from werkzeug import local

ls=local.LocalStack()
x=ls()

class C(abc.ABC):
	pass

isinstance(x, C)

```
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/lib/python3.9/abc.py", line 119, in __instancecheck__
    return _abc_instancecheck(cls, instance)
  File "/usr/lib/python3.9/abc.py", line 123, in __subclasscheck__
    return _abc_subclasscheck(cls, subclass)
TypeError: issubclass() arg 1 must be a class
```

The call to isinstance() should have returned False rather than an exception.

It seems to be related to the fact that `x.__class__` is not a class as expected, but an unbound method. Calling it with `x.__class__()` returns the expected `werkzeug.local.LocalProxy` class. While it's not documented in Python except for builtin types, most of the ecosystem will assume `type(x) is x.__class__`, including it appears the standard library.

Environment:

- Python version: Python 3.9.6
- Werkzeug version: 2.0.1

### Additional contract requirements

- Accessing `__class__` on a `LocalProxy` returns the class of the proxied object when the proxy is bound, and the `LocalProxy` class itself when the proxy is unbound.
- Accessing `__doc__` on a `LocalProxy` returns the docstring of the proxied object's type when the proxy is bound, and the `LocalProxy` class's own docstring when the proxy is unbound.


- For an unbound proxy, `repr(proxy)` must return exactly `"<LocalProxy unbound>"`.
