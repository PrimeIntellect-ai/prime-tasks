Mypy plugin nags about "Missing named argument __config__" on BaseSettings.construct()
### Checks

* [X] I added a descriptive title to this issue
* [X] I have searched (google, github) for similar issues and couldn't find anything
* [X] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.1
            pydantic compiled: True
                 install path: /home/musttu/.pyenv/versions/3.9.4/envs/py39/lib/python3.9/site-packages/pydantic
               python version: 3.9.4 (default, May  3 2021, 13:52:18)  [GCC 9.3.0]
                     platform: Linux-5.8.0-50-generic-x86_64-with-glibc2.31
     optional deps. installed: ['typing-extensions']
```

With `mypy.ini`:

```ini
[mypy]
plugins = pydantic.mypy
```

```py
import pydantic

class Foo(pydantic.BaseSettings):
    pass

Foo.construct()
```

```
$ mypy models.py
models.py:6: error: Missing named argument "__config__" for "construct" of "Foo"
Found 1 error in 1 file (checked 1 source file)
```

Only occurs if pydntic's mypy plugin is enabled. Why is that?
