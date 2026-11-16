Improve error message when `.*` is used incorrectly
The error message here complains about a right parenthesis missing, though that's not the issue:

```python
    raise InvalidRequirement(str(e)) from e
packaging.requirements.InvalidRequirement: Expected closing RIGHT_PARENTHESIS
    black (>=20.*) ; extra == 'format'
          ~~~~~^
```

### Additional contract requirements

- When a version specifier uses the `.*` suffix with an operator other than `==` or `!=` (for example, `black (>=20.*)`), constructing the `Requirement` must raise `InvalidRequirement` whose message contains exactly this text: ``.* suffix can only be used with `==` or `!=` operators``
