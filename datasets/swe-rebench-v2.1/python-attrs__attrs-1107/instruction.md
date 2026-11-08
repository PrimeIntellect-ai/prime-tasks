Add `type` back to `attrs.field()` for use in `attrs.make_class()`
I'm using `attrs.make_class()` to dynamically construct a class based on other attrs classes, and it would be nice to be able to specify the `type` of the fields on the generated class using `attrs.field()` instead of `attr.ib()`. In other words, this works:

```python
fields = {
    field.name: attr.ib(type=field.type)
    for field in itertools.chain.from_iterable(
        attrs.fields(t) for t in SOME_ATTRS_CLASSES
    )
    if not field.name.startswith("_")
}

MyClass = attrs.make_class("MyClass", fields)
```

but this does not:

```python
fields = {
    field.name: attrs.field(type=field.type)
    for field in itertools.chain.from_iterable(
        attrs.fields(t) for t in SOME_ATTRS_CLASSES
    )
    if not field.name.startswith("_")
}

MyClass = attrs.make_class("MyClass", fields)
```

### Additional contract requirements

`attrs.field()` accepts a `type` keyword argument. The value passed is preserved as the field's type metadata: the attribute object obtained from `attrs.fields(cls)` exposes it through its `.type` attribute. This holds both when the field is passed to `attrs.make_class()` and when the field is assigned directly as a class attribute.
