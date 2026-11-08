AttributeError: _cparts
When upgrading to the new version of `universal-pathlib` I'm finding it common in my use case for tools to compare `UPath` instances to `pathlib.Path` instances and raise an `AttributeError`:

```python
import pathlib

from upath import UPath

github_path = UPath("github://fsspec:universal_pathlib@main/README.md")
local_path = pathlib.Path("README.md")

match = github_path == local_path
```

```python
  File "/Users/juftin/Library/Application Support/JetBrains/IntelliJIdea2023.2/scratches/scratch_68.py", line 8, in <module>
    match = github_path == local_path
            ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/juftin/.pyenv/versions/3.11.3/lib/python3.11/pathlib.py", line 581, in __eq__
    return self._cparts == other._cparts and self._flavour is other._flavour
                           ^^^^^^^^^^^^^
  File "/Users/juftin/git/textual-universal-directorytree/.venv/test/lib/python3.11/site-packages/upath/core.py", line 421, in __getattr__
    raise AttributeError(item)
AttributeError: _cparts. Did you mean: '_parts'?
```

I'm not exactly sure what pathlib is doing with `_cparts`, but I'm finding that [HIDDEN] resolves this issue.

### Additional contract requirements

- Comparisons between a `UPath` and a `pathlib.Path` must complete without raising `AttributeError` and use ordinary path-equality semantics in either operand order.
