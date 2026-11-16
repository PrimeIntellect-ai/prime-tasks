22.0: The new requirement parser doesn't handle unnormalized specifiers
```python
from packaging.specifiers import SpecifierSet
from packaging.requirements import Requirement

s = SpecifierSet('>=1.0-alpha')  # success
"1.0a0" in s  # True

r = Requirement('foo>=1.0-alpha')  # Error
```

Ideally, we should make them consistent.

### Additional contract requirements

- When parsing `Requirement('name==')`, the exception diagnostic must be exactly:
```text
packaging.requirements.InvalidRequirement: Expected end or semicolon (after name and no valid version specifier)
    name==
        ^
```
