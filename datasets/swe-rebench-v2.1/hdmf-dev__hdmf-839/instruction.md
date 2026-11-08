[Bug]: Cannot generate custom MultiContainerInterface class with "+"
### What happened?

For a data type spec like the following:
```yaml
data_type_def: MyType
doc: ...
groups:
  - data_type_inc: MySubType
    doc: ...
    quantity: +
```

In the generated class, the generated `__init__` method requires a value for `my_sub_type` because the quantity is "one or more", but for some reason, no value is provided, so docval complains that a required field is missing. This needs more investigation.

### Steps to Reproduce

```shell
will fill out later
```


### Traceback

```shell
will fill out later
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

3.10

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

For a generated multi-container class, a group declared with quantity `+` is a required constructor argument. Supplying the group initializes the instance with the supplied member; omitting the argument is rejected with `TypeError`.
