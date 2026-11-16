Cloning to Path from pathlib no longer work
Since version 2.1.7 using `Path` from `pathlib` to declare path in `Repo.clone_from` doesn't work anymore - it was working fine on 2.1.6 and before.

How to reproduce:

```
pip install gitpython==2.1.7
```

Run

```
from pathlib import Path
from git import Repo

path = Path("test1").resolve()
repo = Repo.clone_from("https://github.com/gitpython-developers/async.git", path)
```

On 2.1.7 it raises `TypeError`

```
Traceback (most recent call last):
  File "script.py", line 6, in <module>
    repo = Repo.clone_from("https://github.com/gitpython-developers/async.git", path)
  File "/home/miki/.pyenv/versions/test_gitpython/lib/python3.6/site-packages/git/repo/base.py", line 972, in clone_from
    return cls._clone(git, url, to_path, GitCmdObjectDB, progress, **kwargs)
  File "/home/miki/.pyenv/versions/test_gitpython/lib/python3.6/site-packages/git/repo/base.py", line 939, in _clone
    repo = cls(path, odbt=odbt)
  File "/home/miki/.pyenv/versions/test_gitpython/lib/python3.6/site-packages/git/repo/base.py", line 125, in __init__
    if expand_vars and ("%" in epath or "$" in epath):
TypeError: argument of type 'PosixPath' is not iterable
```

I am running this on python 3.6.2.
