Any not supported in provider_map
### Description

Trying to use polyfactory with a model with a `typing.Any` field, I cannot seem to cover it in the `get_provider_map`. Using `object` instead of `Any` works as a workaround, but does not feel right.

Related to https://github.com/litestar-org/polyfactory/discussions/515

### URL to code causing the issue

_No response_

### MCVE

```python
from typing import Any

from polyfactory.factories.pydantic_factory import ModelFactory
from pydantic import BaseModel


class WeirdModel(BaseModel):
    any: Any
    obj: object


class Factorio(ModelFactory[WeirdModel]):
    @classmethod
    def get_provider_map(cls) -> dict[type, Any]:
        providers_map = super().get_provider_map()

        return {
            **providers_map,
            Any: lambda: "this does not work",
            object: lambda: "this works as workaround",
        }


print(Factorio().build())
# prints: any='<a random string>' obj='this works as workaround'
# I would expect "this does not work" for any
```


### Steps to reproduce

```bash
Just run the above script (tested with python 3.12) for instance on the command line.
```


### Screenshots

"In the format of: `![SCREENSHOT_DESCRIPTION](SCREENSHOT_LINK.png)`"


### Logs

_No response_

### Release Version

polyfactory==2.15.0
pydantic==2.6.4
pydantic_core==2.16.3

### Platform

- [X] Linux
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

<a href="https://polar.sh/litestar-org/polyfactory/issues/521">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/521/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/521/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->
