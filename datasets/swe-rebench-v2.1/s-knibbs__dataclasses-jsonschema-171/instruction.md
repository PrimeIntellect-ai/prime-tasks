Support discriminators when used with Union types
It should be possible to use discriminators when decoding union fields. Currently discriminators only work when calling `from_dict` on the base class.

Example:

```python
@dataclass
class Base(JsonSchemaMixin, discriminator=True):
    pass


@dataclass
class Foo(Base):
    common_field: int


@dataclass
class Bar(Base):
    common_field: int
    other_field: Optional[int] = None


@dataclass
class Baz(JsonSchemaMixin):
    my_foo_bar: Union[Bar, Foo]
```

This doesn't currently work since, since data can be valid under both the `Foo` and `Bar` schemas and the discriminator field is not checked.
