Can't mix `typing.Protocol` and `typing_extensions.Protocol` anymore as base classes
When inheriting from a typing-based Protocol and a typing-extensions-based Protocol, I get a metaclass error:

```
Python 3.10.11 (main, Apr 20 2023, 19:02:41) [GCC 11.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import typing
>>> import typing_extensions
>>> class P1(typing.Protocol): ...
...
>>> class P2(typing_extensions.Protocol): ...
...
>>> class P3(P1, P2, typing.Protocol): ...
...
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: metaclass conflict: the metaclass of a derived class must be a (non-strict) subclass of the metaclasses of all its bases
>>> class P3(P1, P2, typing_extensions.Protocol): ...
...
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: metaclass conflict: the metaclass of a derived class must be a (non-strict) subclass of the metaclasses of all its bases
```

Is this expected?

(This is with typing-extensions 4.6.3.)

### Additional contract requirements

- A class inheriting from protocols based on both `typing.Protocol` and `typing_extensions.Protocol` must be definable without a metaclass conflict, regardless of base order or which `Protocol` class is included directly as a base.
