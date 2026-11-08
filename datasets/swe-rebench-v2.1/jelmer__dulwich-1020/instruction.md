Dulwich incorrectly parses tracking branches containing `]`
I have something like this in my `.git/config`, which is considered valid by git itself, but breaks Dulwich.

```
[branch "foo]bar"]
        remote = origin
        merge = refs/heads/foo]bar
```

```
>>> from dulwich.repo import Repo
>>> r = Repo('.')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File ".../lib/python3.10/site-packages/dulwich/repo.py", line 1099, in __init__
    config = self.get_config()
  File ".../lib/python3.10/site-packages/dulwich/repo.py", line 1544, in get_config
    return ConfigFile.from_path(path)
  File ".../lib/python3.10/site-packages/dulwich/config.py", line 595, in from_path
    ret = cls.from_file(f)
  File ".../lib/python3.10/site-packages/dulwich/config.py", line 546, in from_file
    raise ValueError("Invalid subsection %r" % pts[1])
ValueError: Invalid subsection b'"foo'
```
