Unrecognized enum values not handled correctly if the field is optional
The following will raise a ValueError when it shouldn't:

```python
    class PetType(Enum):
        CAT = "cat"
        DOG = "dog"

    @dataclass
    class Pet(JsonSchemaMixin):
        name: str
        type: Optional[PetType] = None

    p = Pet.from_dict({'name': 'snakey', 'type': 'python'}, validate_enums=False)
```

[HIDDEN]

```python
                try:
                    values[f.field.name] = cls._decode_field(f.field.name, f.field.type, data.get(f.mapped_name))
                except ValueError:
                    [HIDDEN]

```

### Additional contract requirements

- When `validate_enums=False`, deserializing an unrecognized value for an optional enum field must not raise `ValueError`, and the resulting object must retain the supplied value for that field.
