Bug: Annotations for nested types are ignored
### Description

When a pydantic model contains a simple annotated attribute, the restrictions from the annotation are used for generating the value.

Example:
```python
Dimension = Annotated[int, Field(gt=1000, lt=2000)]

class Item(BaseModel):
    x: Dimension

class ItemFactory(ModelFactory):
    __model__ = Item

print(ItemFactory.build())
```
```
>>> x=1456
```

However, if I change the Item model to

```python
class Item(BaseModel):
    dimensions: list[Dimension]

```
I get the following error saying that polyfactory generated the value 8569
```
>>>
pydantic_core._pydantic_core.ValidationError: 1 validation error for Item
dimensions.0
  Input should be less than 2000 [type=less_than, input_value=8569, input_type=int]
    For further information visit https://errors.pydantic.dev/2.4/v/less_than
```




### URL to code causing the issue

_No response_

### MCVE

```python
from polyfactory.factories.pydantic_factory import ModelFactory
from typing import Annotated
from pydantic import BaseModel, Field

Dimension = Annotated[int, Field(gt=1000, lt=2000)]

class Item(BaseModel):
    dimensions: list[Dimension]


class ItemFactory(ModelFactory):
    __model__ = Item


print(ItemFactory.build())
```


### Steps to reproduce

```bash
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error
```


### Screenshots

"In the format of: `![SCREENSHOT_DESCRIPTION](SCREENSHOT_LINK.png)`"


### Logs

_No response_

### Release Version

2.11.0

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
> Check out all issues funded or available for funding [on our Polar.sh Litestar dashboard](https://polar.sh/litestar-org)
> * If you would like to see an issue prioritized, make a pledge towards it!
> * We receive the pledge once the issue is completed & verified
> * This, along with engagement in the community, helps us know which features are a priority to our users.

<a href="https://polar.sh/litestar-org/polyfactory/issues/434">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/434/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/434/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->
