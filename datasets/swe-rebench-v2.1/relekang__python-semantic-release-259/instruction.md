Unable to specify version_pattern with start/end of line (^ or $)
## The problem

`version_pattern` does not allow for the use of `^` or `$` to signify the start or end of a line. This means that some unwanted matches might be found (examples below)

## Expected behavior

Using `^` or `$` would match the start or end of a line in the target file, as in `multiline` regular expressions.

## Additional context

`pyproject.toml`
```toml
[tool.poetry]
version = "0.1.0"

[tool.semantic_release]
version_pattern = 'pyproject.toml:version = "{version}"'

[tool.pytest.ini_options]
minversion = "6.0"
```

Running `semantic-release --noop version` results in the following:
```console
$ semantic-release --noop version
Creating new version
error: found conflicting versions: '0.1.0', '6.0'
```

[HIDDEN]

## Workarounds

There is a simple way to work around this limitation: specify the inline multiline flag `(?m)` somewhere in the pattern string, e.g.:

```toml
version_pattern = 'pyproject.toml:version = "{version}"(?m)'
```

However, given the use cases for this tool and the places where the version is likely to be, it seems like it might be good to turn on the multiline flag by default.

### Additional contract requirements

- `^` and `$` in `version_pattern` must use multiline anchor semantics by default, without requiring `(?m)` in each configured pattern.
