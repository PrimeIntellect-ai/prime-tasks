@property does not pass from Schema to Accessor
We access Schema `@properties` like `index`, `semantic_tags`, etc via the WoodworkTableAccessor with a `__getattr__` that makes the Schema call. However, the `property` is not being propagated, so users can set those values and interact with them in ways that they couldn't if they directly accessed them through the Schema.

Here's an example of behavior that we don't want to be possible:
```python
df.ww.init()
assert df.ww.index is None

df.ww.index = 'fake_column'

assert df.ww.index == 'fake_column'
assert df.ww.schema.index is None

df.ww.set_index('id')
assert df.ww.index == 'fake_column'
assert df.ww.schema.index == 'id'
```

We can check whether a attr being accessed is a `property` with the following `isinstance(getattr(Schema, attr), property)`, but I'm not sure how we'd go about making that attr a property on the WoodworkTableAccessor class programmatically.

We may need to define the necessary Schema properties on the Accessor. Whether that would mean keeping the properties on the Schema class and wrapping them in the Accessor class or defining them fully on the Accessor is tbd. Likely, we'll still want those properties on the Schema class so that users can interact with a Schema by itself.

Worth noting that to have `index` and `time_index` setters on the Table Accessor, we need to have corresponding getters.
