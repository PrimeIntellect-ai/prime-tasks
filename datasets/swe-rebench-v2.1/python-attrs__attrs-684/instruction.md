Inherited attributes of subclasses no longer compare equal to the equivalent attributes of base class
A change between 19.3.0 → 20.1.0 which doesn't seem to be deliberate, but may be related to #635 is that inherited attributes no longer compare equal to the attributes of the base class. Here is a MWE:

```python
import attr

@attr.s()
class BaseClass(object):
    x = attr.ib()

@attr.s()
class SubClass(BaseClass):
    pass

assert attr.fields(BaseClass)[0].name == attr.fields(SubClass)[0].name   # Succeeds in all versions
assert attr.fields(BaseClass)[0] == attr.fields(SubClass)[0]  # Fails in 20.1.0
```

Interestingly, if you shadow the attribute, it works as expected:

```python
import attr

@attr.s()
class BaseClass(object):
    x = attr.ib()

@attr.s()
class SubClass(BaseClass):
    x = attr.ib()

# Works in all versions
assert attr.fields(BaseClass)[0].name == attr.fields(SubClass)[0].name
assert attr.fields(BaseClass)[0] == attr.fields(SubClass)[0]
```

[HIDDEN]

I discovered this when upgrading some code that does something like this:

```python
import attr

@attr.s()
class BaseClass:
    x = attr.ib()

@attr.s()
class SubClass(BaseClass):
    y = attr.ib()

def f(x) -> None:
    print(x)

def my_function(obj : BaseClass) -> None:
    kwargs = attr.asdict(obj, filter=attr.filters.include(*attr.fields(BaseClass)))
    f(**kwargs)

if __name__ == "__main__":
    my_function(SubClass(1, 2))
```

The idea there is that they want to pull out the subset of the structure that corresponds to the base class.

In this case, I can imagine working around it by pulling out the `name` attribute for each of the `Attribute`s (since in this case I _think_ they would want the subclass to pass along *any* attribute with the name of an attribute on the base class, not just ones that are configured the same way). I can imagine there might be other problems, though, if `attr.filters.include(*attr.fields(BaseClass))` is a common pattern.

### Additional contract requirements

- `Attribute` instances that are otherwise equivalent must compare equal and have equal hashes whether or not one is inherited.
