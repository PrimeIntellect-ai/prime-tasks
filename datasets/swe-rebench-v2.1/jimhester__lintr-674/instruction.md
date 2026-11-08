Warnings from cyclocomp_linter
As part of #653, I ran `lintr::lint_package()`:

```
lintr::lint_package()
```

A ton of warnings were thrown:

```
#Warning messages:
#1: In parent == parent[before_operator_idx] :
#   longer object length is not a multiple of shorter object length
# ...
#653 50: In parent == parent[before_operator_idx] :
#  longer object length is not a multiple of shorter object length
```

At a glance, I suspect that `cyclocomp_linter` is getting tripped up by the `with()` expression:

```
with(
  source_file$parsed_content,
  [HIDDEN]
)
```

But needs more investigation

### Additional contract requirements

- Running `lintr::lint_package()` must not emit vector-length recycling warnings.
