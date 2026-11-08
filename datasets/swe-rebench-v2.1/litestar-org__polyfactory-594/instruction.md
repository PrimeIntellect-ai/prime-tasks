Bug: String length ignored when generating values for SQLAlchemy models
### Description

Polyfactory's `SQLAlchemyFactory` doesn't seem to respect the string length specified when populating a SQLAlchemy model. For example, a field defined as `mapped_column(String(1))` is consistently assigned a 20 character string. Ditto for a field defined as `mapped_column(String(100))`–also consistently a 20 character string. (20 character strings seem to be the default length for the underlying `faker.pystr()` provider.)

### URL to code causing the issue

_No response_

### MCVE

```python
from sqlalchemy import create_engine, Engine, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, Session
from polyfactory.factories.sqlalchemy_factory import SQLAlchemyFactory

class Base(DeclarativeBase): ...

class Cat(Base):
    __tablename__ = "cats"
    id: Mapped[str] = mapped_column(String(10), primary_key=True)
    name: Mapped[str] = mapped_column(String(10))

class CatFactory(SQLAlchemyFactory[Cat]): ...

cat = CatFactory.build()
len(cat.id)   # 20
len(cat.name) # 20
```


### Steps to reproduce

```bash
The MCVE code should be adequate to reproduce the issue with the latest (2.17.0) version of polyfactory.
```

### Release Version

2.17.0

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

<a href="https://polar.sh/litestar-org/polyfactory/issues/592">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/592/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/592/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->
