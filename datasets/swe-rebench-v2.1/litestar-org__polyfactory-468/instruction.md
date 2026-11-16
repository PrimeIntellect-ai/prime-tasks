Support for relationship building models in `SQLAlchemyFactory`
### Summary

Suppose I have a series of cascading models like A, B, C. When I call the factory for A and enable the `__set_relationships__ `parameter, the factory will build model A and have B in each A, but no C in B.
just like:
A
|-B1
    |- Expected C but did not
|-B2
    |- Expected C but did not

I went and read the source code and tried to modify it, and found that it was because the `__set_relationships__` parameter was not set when recursively constructing the factory. When I tried to set the parameter manually it triggered a recursive error, and this feature may require a larger change to the structure of the code.

I am trying to use this library for database mock fake data, if implemented this feature will be able to stage my work.

### Basic Example

Here's a sample test
```py
class Author(Base):
    __tablename__ = "authors"

    id: Any = Column(Integer(), primary_key=True)
    books: Any = orm.relationship(
        "Book",
        uselist=True,
        back_populates="author",
    )


class Book(Base):
    __tablename__ = "books"

    id: Any = Column(Integer(), primary_key=True)
    author_id: Any = Column(
        Integer(),
        ForeignKey(Author.id),
        nullable=False,
    )
    author: Any = orm.relationship(
        Author,
        uselist=False,
        back_populates="books",
    )
    comments: Any = orm.relationship(
        "Comment",
        uselist=True,
        back_populates="book",
    )


class Comment(Base):
    __tablename__ = "comments"

    id: Any = Column(Integer(), primary_key=True)
    book_id: Any = Column(
        Integer(),
        ForeignKey(Book.id),
        nullable=False,
    )
    book: Any = orm.relationship(
        Book,
        uselist=False,
        back_populates="comments",
    )

def test_recursive_relationship_resolution() -> None:
    class AuthorFactory(SQLAlchemyFactory[Author]):
        __model__ = Author
        __set_relationships__ = True

    result = AuthorFactory.build()
    assert isinstance(result.books, list)
    assert isinstance(result.books[0], Book)
    assert isinstance(result.books[0].comments, list)
    assert isinstance(result.books[0].comments[0], Comment)
```

### Drawbacks and Impact

I try add code in
https://github.com/litestar-org/polyfactory/blob/8dc8e1a4594a75ad9a16e1b6f5041b6044fc4f51/polyfactory/factories/base.py#L650C1-L650C80

like that
```py
if BaseFactory.is_batch_factory_type(annotation=unwrapped_annotation):
    factory = cls._get_or_create_factory(model=field_meta.type_args[0])
    if hasattr(factory, '__set_relationships__'):
        setattr(factory, '__set_relationships__', getattr(cls, '__set_relationships__'))
    ......
```
This only solves recursive construction in one-to-many or many-to-many relationships and is very inelegant, raising recursion errors when I try to extend it to one-to-one or many-to-one relationships.

like that
```py
if BaseFactory.is_factory_type(annotation=unwrapped_annotation):
    factory = cls._get_or_create_factory(model=unwrapped_annotation)
    if hasattr(factory, '__set_relationships__'):
        setattr(factory, '__set_relationships__', getattr(cls, '__set_relationships__'))

    return factory.build(
        **(field_build_parameters if isinstance(field_build_parameters, Mapping) else {}),
    )
```


### Unresolved questions

_No response_

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

<a href="https://polar.sh/litestar-org/polyfactory/issues/467">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://polar.sh/api/github/litestar-org/polyfactory/issues/467/pledge.svg?darkmode=1">
  <img alt="Fund with Polar" src="https://polar.sh/api/github/litestar-org/polyfactory/issues/467/pledge.svg">
</picture>
</a>
<!-- POLAR PLEDGE BADGE END -->

### Additional contract requirements

Recursive relationship building is configured through a base factory: a `SQLAlchemyFactory` subclass with `__is_base_factory__ = True` and `__set_relationships__ = True`. Model-specific factories created from that base factory with `create_factory` recursively build nested relationships, so that building `Author` produces `Author.books[0].comments[0]` as a `Comment` instance (and the reverse relationships are populated consistently).
