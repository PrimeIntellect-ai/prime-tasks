Bug: SQLAlchemy instance build fails for models with nullable constraints
### Description

`ModelSQLAlchemyFactory.build()` fails on SQLAlchemy models with a constrained, optional field, e.g., `mapped_column(String(10), nullable=True)`.

With `nullable=False`, no exception is raised.

The bug may have been introduced by #594 that has just been released (2024.11.06 - v2.18.0).

### URL to code causing the issue

_No response_

### MCVE

```python
from polyfactory.factories.sqlalchemy_factory import SQLAlchemyFactory
from sqlalchemy import Integer, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class MyModel(Base):
    __tablename__ = "my_model"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str | None] = mapped_column(String(10), nullable=True)


class MyModelFactory(SQLAlchemyFactory[MyModel]):
    __model__ = MyModel


MyModelFactory.build()
```


### Steps to reproduce

_No response_

### Screenshots

_No response_

### Logs

```bash
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[5], line 20
     16 class MyModelFactory(SQLAlchemyFactory[MyModel]):
     17     __model__ = MyModel
---> 20 MyModelFactory.build()

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/factories/base.py:1080, in BaseFactory.build(cls, **kwargs)
   1071 @classmethod
   1072 def build(cls, **kwargs: Any) -> T:
   1073     """Build an instance of the factory's __model__
   1074
   1075     :param kwargs: Any kwargs. If field names are set in kwargs, their values will be used.
   (...)
   1078
   1079     """
-> 1080     return cast("T", cls.__model__(**cls.process_kwargs(**kwargs)))

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/factories/base.py:980, in BaseFactory.process_kwargs(cls, **kwargs)
    977 result: dict[str, Any] = {**kwargs}
    978 generate_post: dict[str, PostGenerated] = {}
--> 980 for field_meta in cls.get_model_fields():
    981     field_build_parameters = cls.extract_field_build_parameters(field_meta=field_meta, build_args=kwargs)
    982     if cls.should_set_field_value(field_meta, **kwargs) and not cls.should_use_default_value(field_meta):

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/factories/sqlalchemy_factory.py:196, in SQLAlchemyFactory.get_model_fields(cls)
    193 fields_meta: list[FieldMeta] = []
    195 table: Mapper = inspect(cls.__model__)  # type: ignore[assignment]
--> 196 fields_meta.extend(
    197     FieldMeta.from_type(
    198         annotation=cls.get_type_from_column(column),
    199         name=name,
    200         random=cls.__random__,
    201     )
    202     for name, column in table.columns.items()
    203     if cls.should_column_be_set(column)
    204 )
    205 if cls.__set_relationships__:
    206     for name, relationship in table.relationships.items():

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/factories/sqlalchemy_factory.py:197, in <genexpr>(.0)
    193 fields_meta: list[FieldMeta] = []
    195 table: Mapper = inspect(cls.__model__)  # type: ignore[assignment]
    196 fields_meta.extend(
--> 197     FieldMeta.from_type(
    198         annotation=cls.get_type_from_column(column),
    199         name=name,
    200         random=cls.__random__,
    201     )
    202     for name, column in table.columns.items()
    203     if cls.should_column_be_set(column)
    204 )
    205 if cls.__set_relationships__:
    206     for name, relationship in table.relationships.items():

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/field_meta.py:153, in FieldMeta.from_type(cls, annotation, random, name, default, constraints, randomize_collection_length, min_collection_length, max_collection_length, children)
    142     annotation = container[get_args(annotation)]  # type: ignore[index]
    144 field = cls(
    145     annotation=annotation,
    146     random=random,
   (...)
    150     constraints=constraints,
    151 )
--> 153 if field.type_args and not field.children:
    154     field.children = [
    155         cls.from_type(
    156             annotation=unwrap_new_type(arg),
   (...)
    160         if arg is not NoneType
    161     ]
    162 return field

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/field_meta.py:96, in FieldMeta.type_args(self)
     90 @property
     91 def type_args(self) -> tuple[Any, ...]:
     92     """Return the normalized type args of the annotation, if any.
     93
     94     :returns: a tuple of types.
     95     """
---> 96     return tuple(TYPE_MAPPING.get(arg, arg) for arg in get_args(self.annotation))

File ~/toy-project/.venv/lib/python3.12/site-packages/polyfactory/field_meta.py:96, in <genexpr>(.0)
     90 @property
     91 def type_args(self) -> tuple[Any, ...]:
     92     """Return the normalized type args of the annotation, if any.
     93
     94     :returns: a tuple of types.
     95     """
---> 96     return tuple(TYPE_MAPPING.get(arg, arg) for arg in get_args(self.annotation))

File /usr/lib/python3.12/typing.py:2023, in _AnnotatedAlias.__hash__(self)
   2022 def __hash__(self):
-> 2023     return hash((self.__origin__, self.__metadata__))

TypeError: unhashable type: 'dict'
```


### Release Version

v2.18.0

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

<a href="https://polar.sh/litestar-org/polyfactory/issues/601">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/601/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/601/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

Building a SQLAlchemy model with a constrained nullable or optional field must succeed. If the generated value is non-null, it must satisfy the constraints declared by its SQL type.
