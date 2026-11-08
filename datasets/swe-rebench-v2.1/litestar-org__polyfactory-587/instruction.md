Bug: Recursive model in a dictionary fails to generate
### Description

I saw that recursive type got introduced recently, they seem to work fine under the tested scenarios, however I had an issue with the code sample below where the recursivity occurs within a dictionary.

### MCVE

```python
from polyfactory.factories.pydantic_factory import ModelFactory
from pydantic import BaseModel
from __future__ import annotations

class Recursive(BaseModel):
    nested: dict[str,Recursive]
factory = ModelFactory.create_factory(Recursive)
instance = factory.build()
```

The code above throws the following error:
```
ValidationError: 1 validation error for Recursive
next.ZMmfLLwXbzrHxjwdxFXt
  Input should be a valid dictionary or instance of Recursive [type=model_type, input_value=<class 'polyfactory.field_meta.Null'>, input_type=type]
    For further information visit https://errors.pydantic.dev/2.9/v/model_type
```

### Release Version

2.16.2

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
> Check out all issues funded or available for funding [on our Polar.sh dashboard](https://polar.sh/litestar-org)
> * If you would like to see an issue prioritized, make a pledge towards it!
> * We receive the pledge once the issue is completed & verified
> * This, along with engagement in the community, helps us know which features are a priority to our users.

<a href="https://polar.sh/litestar-org/polyfactory/issues/585">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/585/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/585/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

- For the tested recursive `PydanticNode` model, `build()` must produce `result.recursive_key == {}` and `result.recursive_value == {}`.
