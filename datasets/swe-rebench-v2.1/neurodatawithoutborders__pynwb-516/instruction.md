Add NWBRefSpec class
## 2) Feature Request

For consistency, it would be good to add a ``NWBRefSpec` ` class just so that all the spec classes from form have a counterpart in ``pynwb.spec``.  Currently this class would not need to define Iany custom behavior so it would be just a primitive class:

```
[HIDDEN]
```

### Problem/Use Case

The primary use-case is to simplify and improve consistency of imports needed when creating extensions to enable that all spec classes can be imported directly from ``pynwb.spec``.

## Checklist

- [X ] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [X] Have you included a brief and descriptive title?
- [X] Have you included a clear description of the problem you are trying to solve?
- [X] Have you included a minimal code snippet that reproduces the issue you are encountering?

### Additional contract requirements

- `NWBRefSpec` must be importable directly from `pynwb.spec` for use when creating extensions.
- It must be a subtype of `RefSpec` and retain its reference-spec behavior: construction accepts `target_type` and `reftype`, exposes those values on the instance, and raises `ValueError` for unsupported reference types.
