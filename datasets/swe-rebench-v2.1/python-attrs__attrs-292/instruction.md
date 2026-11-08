Type hint defaults don't work with inheritance
Consider

```
In [12]: @attr.s(auto_attribs=True)
    ...: class A:
    ...:     a: int = 10
    ...:

In [13]: @attr.s(auto_attribs=True)
    ...: class B(A):
    ...:     pass
    ...:

In [14]: A()
Out[14]: A(a=10)

In [15]: B()
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-15-1c5ecc61f85b> in <module>()
----> 1 B()

TypeError: __init__() missing 1 required positional argument: 'a'

```

This should work, given that the following works:

```
In [16]: @attr.s()
    ...: class A:
    ...:     a = attr.ib(default=10)
    ...:

In [17]: @attr.s()
    ...: class B(A):
    ...:     pass
    ...:

In [18]: A()
Out[18]: A(a=10)

In [19]: B()
Out[19]: B(a=10)

```

### Additional contract requirements

With `@attr.s(auto_attribs=True)`, a subclass must retain its superclass's annotated attributes and their defaults even when the subclass declares its own annotated attribute. The subclass can be constructed without arguments when its inherited and locally declared attributes all have defaults.
