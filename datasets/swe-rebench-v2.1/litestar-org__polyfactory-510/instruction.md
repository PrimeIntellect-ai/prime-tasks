Bug: Try to use SQLAlchemyFactory for model with column_property
### Description

Create model with declared `column_property` and try create model object with it.

Got error `AttributeError: Neither 'Label' object nor 'Comparator' object has an attribute 'nullable'`

### URL to code causing the issue

_No response_

### MCVE

```python
from sqlalchemy import Integer, String
from sqlalchemy.orm import DeclarativeBase, column_property, mapped_column

from polyfactory.factories.sqlalchemy_factory import SQLAlchemyFactory


class Base(DeclarativeBase):
    ...


class Student(Base):
    __tablename__ = "user"
    id = mapped_column(Integer(), primary_key=True)
    firstname = mapped_column(String(50))
    lastname = mapped_column(String(50))
    fullname = column_property(firstname + " " + lastname)


class StudentFactory(SQLAlchemyFactory[Student]):
    __model__ = Student
    __set_relationships__ = True
    __set_foreign_keys__ = False


student = StudentFactory.build()
```


### Steps to reproduce

```bash
1. Define SQLAlchemy model with column_property
2. Define SQLAlchemyFactory with model
3. Try to create object with factory
```


### Screenshots

_No response_

### Logs

```bash
tests/test_api/test_student/test_change_teacher.py:100:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.venv/lib/python3.11/site-packages/polyfactory/factories/base.py:1031: in build
    return cast("T", cls.__model__(**cls.process_kwargs(**kwargs)))
.venv/lib/python3.11/site-packages/polyfactory/factories/base.py:931: in process_kwargs
    for field_meta in cls.get_model_fields():
.venv/lib/python3.11/site-packages/polyfactory/factories/sqlalchemy_factory.py:141: in get_model_fields
    fields_meta.extend(
.venv/lib/python3.11/site-packages/polyfactory/factories/sqlalchemy_factory.py:143: in <genexpr>
    annotation=cls.get_type_from_column(column),
[HIDDEN]
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <sqlalchemy.sql.elements.Label at 0x1079e01d0; %(4422762960 anon)s>, key = 'nullable'

    def __getattr__(self, key: str) -> Any:
        try:
            return getattr(self.comparator, key)
        except AttributeError as err:
>           raise AttributeError(
                "Neither %r object nor %r object has an attribute %r"
                % (
                    type(self).__name__,
                    type(self.comparator).__name__,
                    key,
                )
            ) from err
E           AttributeError: Neither 'Label' object nor 'Comparator' object has an attribute 'nullable'

.venv/lib/python3.11/site-packages/sqlalchemy/sql/elements.py:1604: AttributeError
----------------------------------------------------------------- Captured stderr setup -----------------------------------------------------------------
Context impl PostgresqlImpl.
Will assume transactional DDL.
----------------------------------------------------------------- Captured stdout call ------------------------------------------------------------------
student.first_name || :param_1 || student.last_name  # add my print to find a column with problem
```


### Release Version

2.9.0

### Platform

- [X] Linux
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

<a href="https://polar.sh/litestar-org/polyfactory/issues/508">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/508/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/508/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

- When `SQLAlchemyFactory.build()` creates an unpersisted model with an expression-backed `column_property` such as `double_age`, the property value must be `None`.
- `SQLAlchemyFactory.build()` must successfully create an unpersisted model instance that declares an expression-backed `column_property`; processing that property must not raise an error.
