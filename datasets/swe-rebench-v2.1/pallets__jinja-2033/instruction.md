`MutableSequence` coverage in `ImmutableSandboxedEnvironment`
I happened to notice in using `ImmutableSandboxedEnvironment` that the default `modifies_known_mutable` check seems to be missing coverage for a couple of methods. In particular the `clear` and `pop` methods are checked for both `MutableMapping` and `MutableSet` but not `MutableSequence`.

Example:
```python
from jinja2.sandbox import ImmutableSandboxedEnvironment

env = ImmutableSandboxedEnvironment()
print(env.from_string("{{ [1].pop() }}").render())
```

Expected: `SecurityError` should be raised
Actual: `1` is printed

Environment:

- Python version: 3.10
- Jinja version: 3.1.4
