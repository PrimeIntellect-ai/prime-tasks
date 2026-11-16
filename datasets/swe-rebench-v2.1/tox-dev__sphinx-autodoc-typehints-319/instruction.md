Event 'autodoc-process-docstring' threw an exception (exception: unhashable type: 'ParamSpecArgs')
Autodoc 1.21.8 fails for a ParamSpec

```python
HINT_CB_P = ParamSpec('HINT_CB_P')
HINT_CB: TypeAlias = Callable[HINT_CB_P, Any]


class MyClass):
    def func(self, callback: HINT_CB, *args: HINT_CB_P.args, **kwargs: HINT_CB_P.kwargs):
        pass
```

Error:
```
    [HIDDEN]
TypeError: unhashable type: 'ParamSpecArgs'
```

https://github.com/tox-dev/sphinx-autodoc-typehints/blob/d9c4a06b654f4415d61e5ce23f46c8356a6ab92a/src/sphinx_autodoc_typehints/__init__.py#L39
