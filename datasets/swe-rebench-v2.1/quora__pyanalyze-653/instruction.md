False positive (incompatible_override) with properties
I am surprised how this feature could detect many cases that mypy could not after running it into one of my repos. However, it seems that `@property` makes this tool raise `incompatible_override` when overriding a property. I will try later if it also fails with `@typing.override`

Minimal example that triggers this issue:
```python
class A:

    @property
    def prop(self):
        return ()

class B(A):

    @property
    def prop(self):
        return ("New tuple",)
```

Output:

```shell
Value of prop incompatible with base class <class 'delete.A'> (code: incompatible_override)
  Base class: 'Literal[<property object at 0x000002682790C6D0>]'
  Child class: 'Literal[<property object at 0x00000268294BFB50>]'
  Cannot assign Literal[<property object at 0x00000268294BFB50>] to Literal[<property object at 0x000002682790C6D0>]
```
