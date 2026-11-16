Bug: Required fields in TypedDicts throw exceptions
### Description

Hello, thanks for this super useful library! I was trying out polyfactory with some TypedDicts and it throws an exception. Not sure if this should be classified as a bug or a feature request, but wanted to bring it to your attention in any case.

### URL to code causing the issue

_No response_

### MCVE

```python
from typing_extensions import TypedDict, Required
from polyfactory.factories import TypedDictFactory

class Foo(TypedDict, total=False):
    name: Required[str]
    bar: str

class FooFactory(TypedDictFactory[Foo]):
    __model__ = Foo
```


### Steps to reproduce

```bash
Run `FooFactory.build()`, and I get the exception: `TypeError: Required accepts only a single type. Got (<class 'str'>,).`
```


### Screenshots

_No response_

### Logs

_No response_

### Release Version

Version: 2.10.0

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

<a href="https://polar.sh/litestar-org/polyfactory/issues/421">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/421/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/421/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

- When building a `TypedDict` with a `NotRequired[str]` field, the returned dictionary must include that field with a string value.
