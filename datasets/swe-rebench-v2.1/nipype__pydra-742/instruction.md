TypeError: TypeParser doesn't know how to handle args ((<class 'pathlib.Path'>, <class 'NoneType'>)) for <class 'types.UnionType'>
The following task definition:

```python
@task
@annotate({"return": {"smoothed_image": Path}})
def smooth_image(input_image: Path, smoothed_image: Path | None) -> Path:
    ...
```

triggers an error:

`TypeError: TypeParser doesn't know how to handle args ((<class 'pathlib.Path'>, <class 'NoneType'>)) for <class 'types.UnionType'> types in 'smoothed_image' field of Inputs `

Notation `X | None` is becoming popular, and sometimes autoformatted by linters like Ruff. It would be great if Pydra's internal parsing mechanism were able to inject the necessary required / optional metadata to the fields, or at least not crash since this is a valid function definition.

### Additional contract requirements

- `pydra.utils.typing.TypeParser.is_instance(cls, obj, candidates)` must accept `None` as the class argument or as a candidate type, treating `None` as `type(None)`, and must handle `Union` and PEP 604 `|` types (including unions containing `None`) without raising.
- `pydra.utils.typing.TypeParser` must handle `Union` and PEP 604 `|` types (including unions containing `None`) in `is_subclass`, `matches_type`, and in coercion.
- On Python 3.10 and later, `pydra.utils.hash.join_bytes_repr(int | float)` must return `b"type:(types.UnionType[type:(builtins.int)type:(builtins.float)])"` and `pydra.utils.hash.join_bytes_repr(Path | None)` must return `b"type:(types.UnionType[type:(pathlib.Path)type:(builtins.NoneType)])"`.
