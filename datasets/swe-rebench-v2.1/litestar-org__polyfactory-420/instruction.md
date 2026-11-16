Bug: Can't consistently override optional fields with nested models
### Description

When trying to build a nested set of models, if one of them is optional / can be `None`, then there's a chance the factory will assign `None` to the corresponding field even if an explicit value is being passed when calling `build` (see example).

### URL to code causing the issue

_No response_

### MCVE

```python
from dataclasses import dataclass
from polyfactory.factories import DataclassFactory

@dataclass
class Bar:
    baz: str

@dataclass
class Foo:
    bar: Bar | None

class FooFactory(DataclassFactory):
    __model__ = Foo

for _ in range(1000):
    foo = FooFactory.build(bar={'baz': 'TEST'})
    # foo.bar should consistently be present
    assert foo.bar is not None
```


### Steps to reproduce

_No response_

### Screenshots

_No response_

### Logs

_No response_

### Release Version

2.10.0

### Platform

- [ ] Linux
- [X] Mac
- [ ] Windows
- [ ] Other (Please specify in the description above)

<!-- POLAR PLEDGE BADGE START -->
---
> [!NOTE]
> While we are open for sponsoring on [GitHub Sponsors](https://github.com/sponsors/litestar-org/) and
> [OpenCollective](https://opencollective.com/litestar), we also utilize [Polar.sh](https://polar.sh/) to engage in pledge-based sponsorship.
>
> Check out all issues funded or available for funding [on our Polar.sh Litestar dashboard](https://polar.sh/litestar-org)
> * If you would like to see an issue prioritized, make a pledge towards it!
> * We receive the pledge once the issue is completed & verified
> * This, along with engagement in the community, helps us know which features are a priority to our users.

<a href="https://polar.sh/litestar-org/polyfactory/issues/419">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/419/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/419/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

- `polyfactory.factories.base.BaseFactory` exposes a public classmethod `should_set_none_value(cls, field_meta: FieldMeta) -> bool` that returns whether `None` may be assigned to the given field. A factory subclass may override this method to control `None` handling for optional or nullable fields.
- `polyfactory.field_meta.FieldMeta` is the public type describing a model field that is passed to `should_set_none_value`.
