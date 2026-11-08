Support for subclass type specialization
Some guidance on whether this is a good or bad idea, but I'd like to do something like this:

```python
@dataclass
class BaseObject(JsonSchemaMixin):
    field: str

@dataclass
class NarrowedObject(BaseMessage, JsonSchemaMixin):
    field: Literal['staticstr']
```

[HIDDEN] I'm happy to contribute, unless there is a reason _not_ to do this.

### Additional contract requirements

- When a dataclass subclass redeclares an inherited field with a narrower type, `JsonSchemaMixin.json_schema()` must preserve the inherited schema and reflect the narrowed type in the subclass schema. A `Literal` annotation must be represented by its allowed values as an enum.
