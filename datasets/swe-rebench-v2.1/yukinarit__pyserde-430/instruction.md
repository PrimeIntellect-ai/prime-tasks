`alias` on `Optional` field breaks deserialization
Hi there,

Using the latest version (0.12.2), this example consistently deserializes `Foo.a` to `None`:
```py
@serde
@dataclass
class Foo:
    a: Optional[int] = field(alias=["b"])

x = from_json(Foo, '{"b": 1}')
assert x.a == 1 💥
```
