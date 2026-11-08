If `diff.external` is set, diffing via API fails silently as external tool isn't understood
GitPython version: 3.1.42.

```python
from git import Repo

repo = Repo(".")
print(repo.index.diff("HEAD"))
print(repo.index.diff("HEAD", create_patch=True))

print(repo.index.diff(None))
print(repo.index.diff(None, create_patch=True))
```

prints

```python
[<git.diff.Diff object at 0x10cbb08b0>]
[]
[<git.diff.Diff object at 0x103d49d30>]
[]
```

`R=True` workaround mentioned in #852 does not help either:

```python
print(repo.index.diff("HEAD", create_patch=True, R=True))
# []
```

This also happens when I try to diff tree against index or working tree

```python
print(repo.head.commit.diff(None, create_patch=True))
print(repo.head.commit.diff(None))

print(repo.head.commit.diff())
print(repo.head.commit.diff(create_patch=True))

```

returns

```python
[]
[<git.diff.Diff object at 0x103d69670>, <git.diff.Diff object at 0x103d699d0>]
[]
[<git.diff.Diff object at 0x103d69700>]
```

It looks like using `create_patch=True` when comparison includes index or working tree always returns empty list. So right now only way to reliably use `create_patch=True` is to diff tree against tree.

_Originally posted by @can-taslicukur in https://github.com/gitpython-developers/GitPython/issues/852#issuecomment-1951424734_
