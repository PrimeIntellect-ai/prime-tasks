`from_type` raises TypeError for `Union` of builtin generic types
On the current version of hypothesis (6.17.4) on python 3.9.2

```python
st.from_type(Union[list[str], str]).example()
```

raises `TypeError("issubclass() arg 1 must be a class")` because `list[int]` is an instance of `types.GenericAlias` and not an instance of `type`.

### Additional contract requirements

`hypothesis.strategies.from_type` raises `hypothesis.errors.InvalidArgument` when its argument is not a type or a typing construct that resolves to a type (for example, an `int` or a `str` value).
