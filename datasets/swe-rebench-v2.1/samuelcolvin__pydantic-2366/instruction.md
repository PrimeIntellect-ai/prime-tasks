Issue with BaseModel if used with importlib
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.3
            pydantic compiled: True
                 install path: /opt/conda/lib/python3.8/site-packages/pydantic
               python version: 3.8.2 (default, Mar 25 2020, 17:03:02)  [GCC 7.3.0]
                     platform: Linux-4.15.0-130-generic-x86_64-with-glibc2.10
     optional deps. installed: ['typing-extensions']
```

If I'm trying to load a module using `importlib` where a BaseModel is used then execution is crashed with the following traceback:
```
Traceback (most recent call last):
  File "loader.py", line 13, in <module>
    m = load_module("module_to_load.py")
  File "loader.py", line 7, in load_module
    spec.loader.exec_module(module)  # type: ignore[union-attr]
  File "<frozen importlib._bootstrap_external>", line 783, in exec_module
  File "<frozen importlib._bootstrap>", line 219, in _call_with_frames_removed
  File "module_to_load.py", line 4, in <module>
    class User(BaseModel):
  File "pydantic/main.py", line 274, in pydantic.main.ModelMetaclass.__new__
  File "pydantic/typing.py", line 293, in pydantic.typing.resolve_annotations
    def __copy__(self):
```

How to repro:
1) create `loader.py` file with the following content
```python
import importlib.util

def load_module(fpath):
    spec = importlib.util.spec_from_file_location("mymodule", fpath)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # type: ignore[union-attr]
    return module

if __name__ == "__main__":
    m = load_module("module_to_load.py")
    print(m)
    m.foo()
```

2) create `module_to_load.py` :
```python
from pydantic import BaseModel

class User(BaseModel):
    id: int
    name = 'Jane Doe'

def foo():
    print(User(id=12, name="test"))
```

3) Run `python loader.py`


As use-case may seem strange, I'm a bit hestiating between a bug and wrong usage, but in the latter case, error message is unclear at all. Important part is that I have to import the module in this way and not in any other more standard python way in which pydantic indeed work without any issue.
Thanks


EDIT:

Indeed, if we add `sys.modules["mymodule"] = module` to `load_module` as suggested [here](https://docs.python.org/3/library/importlib.html?highlight=exec_module#importing-a-source-file-directly), there is no issue, anymore.
I have to figure out what would be the impact of doing that for my goal.
