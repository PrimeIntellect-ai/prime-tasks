undefined name '__annotations__' when use __annotations__ in module level
Environment:
- Python==3.7.1
- pyflakes==2.0.0

When using pyflake to check following code:

```Python3
# t.py
a: int = 2
print(__annotations__)
```

It will reported that

```
t.py:3: undefined name '__annotations__'
```
About `__annotations__`, please see [PEP 526 -- Syntax for Variable Annotations](https://www.python.org/dev/peps/pep-0526/)
> In addition, at the module or class level, if the item being annotated is a simple name, then it and the annotation will be stored in the `__annotations__` attribute of that module or class (mangled if private) as an ordered mapping from names to evaluated annotations.

And `__annotations__` is not a [`builtin_vars`](https://github.com/PyCQA/pyflakes/blob/master/pyflakes/checker.py#L21), so it will not found.

[HIDDEN]

If you accept this solution, I will pull request to fix it :)

### Additional contract requirements

- In Python 3.6 and later, a module-level use of `__annotations__` must not be reported as an undefined name.
