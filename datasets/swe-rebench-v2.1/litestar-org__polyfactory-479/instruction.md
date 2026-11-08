Bug: settings `__set_as_default_factory_for_type__ ` to `True` on base factory fails
### Description

If `__set_as_default_factory_for_type__ ` is set to `True` on a custom base factory so that all the subclasses factories inherit that value, then an `AttributeError` is raised.

### URL to code causing the issue

_No response_

### MCVE

```python
from polyfactory.factories import DataclassFactory
from polyfactory.factories.base import T


class CustomDataclassBaseFactory(DataclassFactory[T]):
    __is_base_factory__ = True
    __set_as_default_factory_for_type__ = True
```


### Steps to reproduce

```bash
Run the MCVE.
```


### Screenshots

_No response_

### Logs

_No response_

### Release Version

2.13.0

### Platform

- [ ] Linux
- [ ] Mac
- [ ] Windows
- [ ] Other (Please specify in the description above)

<!-- POLAR PLEDGE BADGE START -->
---
> [!NOTE]
> While we are open for sponsoring on [GitHub Sponsors](https://github.com/sponsors/litestar-org/) and
> [OpenCollective](https://opencollective.com/litestar), we also utilize [Polar.sh](https://polar.sh/) to engage in pledge-based sponsorship.
>
> Check out all issues funded or available for funding [on our Polar.sh dashboard](https://polar.sh/litestar-org)
> * If you would like to see an issue prioritized, make a pledge towards it!
> * We receive the pledge once the issue is completed & verified
> * This, along with engagement in the community, helps us know which features are a priority to our users.

<a href="https://polar.sh/litestar-org/polyfactory/issues/476">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/476/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/476/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->
