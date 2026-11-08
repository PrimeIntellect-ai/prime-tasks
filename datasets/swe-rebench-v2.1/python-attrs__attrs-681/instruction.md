Using slots class overrides custom `__setattr__` in 20.1.0
In 19.3.0, it was possible to have a custom `__setattr__` on your `slots` class, but in 20.1.0 the custom `__setattr__` is replaced with the default one:

```python
import attr
@attr.s(slots=True)
class A:
    def __setattr__(self, key, value):
        print(f"{key}: {value}")
```

In 19.3.0:

```python
>>> A().a = 3
a: 3
```

In 20.1.0:

```python
>>> A().a = 3
AttributeError: 'A' object has no attribute 'a'
>>> A.__setattr__
<slot wrapper '__setattr__' of 'object' objects>
```

When `slots=False`, the same thing does not occur.
