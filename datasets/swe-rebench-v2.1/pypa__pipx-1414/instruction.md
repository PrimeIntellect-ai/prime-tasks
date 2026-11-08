Look into ruff rule RUF012
**How would this feature be useful?**

[`RUF012`](https://docs.astral.sh/ruff/rules/mutable-class-default/) checks for mutable default values in class attributes:
> Mutable default values share state across all instances of the class, while not being obvious. This can lead to bugs when the attributes are changed in one instance, as those changes will unexpectedly affect all other instances.

```console
$ ruff check --extend-select RUF --ignore RUF005
src/pipx/animate.py:24:20: RUF012 Mutable class attributes should be annotated with `typing.ClassVar`
src/pipx/pipx_metadata_file.py:40:28: RUF012 Mutable class attributes should be annotated with `typing.ClassVar`
src/pipx/pipx_metadata_file.py:41:29: RUF012 Mutable class attributes should be annotated with `typing.ClassVar`
src/pipx/pipx_metadata_file.py:42:44: RUF012 Mutable class attributes should be annotated with `typing.ClassVar`
src/pipx/pipx_metadata_file.py:43:56: RUF012 Mutable class attributes should be annotated with `typing.ClassVar`
Found 5 errors.
$
```

Introduced in #610:
https://github.com/pypa/pipx/blob/5eed47950ba97ea8e0ad292a1026cf87809f940e/src/pipx/animate.py#L23-L24

Introduced in #222:
https://github.com/pypa/pipx/blob/5eed47950ba97ea8e0ad292a1026cf87809f940e/src/pipx/pipx_metadata_file.py#L29-L44

**Describe the solution you'd like**

As a first step, I'd like to understand whether this is on purpose or not.

I suspect the relevant classes are designed to have one instance, in which case this is not an issue in practice. Nevertheless, it's good practice to avoid mutable default values, so that future maintainers don't have to ask themselves again.

**Describe alternatives you've considered**

### Additional contract requirements

- Mutable collection defaults in package metadata must be independent between instances: mutating a default collection on one instance must not change the corresponding collection on another instance.
- The reported `RUF012` violations must be resolved.
