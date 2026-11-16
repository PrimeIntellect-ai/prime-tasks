Optional type check fails with optional union type
The following type does not currently get identified as optional:
```python
Optional[Union[int, float]]
```

This is because the code is [HIDDEN] but does not take into account the flattening of `Union` types (`Optional` is an alias of `Union[T, type(None)]`).

### Additional contract requirements

- A field annotated as `Optional[Union[...]]` is recognized as optional: it is not listed in the generated schema's `required` array.
- Union field types are represented compositionally using `oneOf`; the order of the `oneOf` alternatives is not significant.
