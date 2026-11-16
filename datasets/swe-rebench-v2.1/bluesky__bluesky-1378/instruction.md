check of isinstance(obj, Movable) only accepts class attributes, rejecting potentially valid objects
I'm trying to get yaqc-bluesky settable objects to work in a `grid_scan`, but bluesky is claiming that my arguments are invalid. In particular, my objects are failing to pass `isinstance(obj, Movable)` [1].

The `Movable` class is an abstract base class [2] which, according to the comment, should turn the `isinstance` check into, essentially, a check against the list of expected attributes. Not actually understanding the ABC magic, all I can say is that I can pass `hasattr` without passing `isinstance`:

```python
import bluesky
from bluesky.utils import Movable


EXPECTED_ATTRS = (
    'name',
    'parent',
    'read',
    'describe',
    'read_configuration',
    'describe_configuration',
    'set',
    'stop',
)


class Device(object):

    def __init__(self):
        for attr in EXPECTED_ATTRS:
            setattr(self, attr, None)


device = Device()
print("hasattr", all(hasattr(device, attr) for attr in EXPECTED_ATTRS))  # True
print("isinstance", isinstance(device, Movable))  # False
print("subclasshook", Movable.__subclasshook__(device))  # True
```

Even more strangely, when I play with your example notebook [3] your own ophyd motor objects also fail this `isinstance` check and, indeed, are rejected within `grid_scan` (Hello Bluesky.ipynb). Is it possible that this plan is just broken?

Any guidance would be appreciated---thanks! :smile:

[1] https://github.com/bluesky/bluesky/blob/master/bluesky/plan_patterns.py#L431
[2] https://github.com/bluesky/bluesky/blob/master/bluesky/utils.py#L1519-L1548
[3] https://try.nsls2.bnl.gov/

### Additional contract requirements

- The argument classification used by `grid_scan` must accept objects that satisfy the movable interface through instance attributes. Concretely, `bluesky.plan_patterns.classify_outer_product_args_pattern` must recognize such an object as a movable: for an argument list of the form `(motor, start, stop, num)` it returns `OuterProductArgsPattern.PATTERN_1` instead of raising `ValueError`.
