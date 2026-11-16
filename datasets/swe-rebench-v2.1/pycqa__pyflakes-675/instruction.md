Internal error on `__all__, = ...`
Steps to reproduce:
1. Install `pyflakes==2.4.0`
2. Create a file with the name of `foo.py`
3. Place the following in the file (the comma after `__all__` is intentional):
```py
__all__, = (
    "fizz",
    "buzz",
)
```
4. Run `pyflakes foo.py`

Outcome:
```
Traceback (most recent call last):
  File "/tmp/foo/venv/bin/pyflakes", line 8, in <module>
    sys.exit(main())
...
  File "/tmp/foo/venv/lib/python3.9/site-packages/pyflakes/checker.py", line 591, in __init__
    if isinstance(source.value, (ast.List, ast.Tuple)):
AttributeError: 'Tuple' object has no attribute 'value'
```

[HIDDEN]

I think the right behaviour is to mark this as invalid to the user.

I'd be happy to work on this issue myself.

### Additional contract requirements

- When `__all__` is bound through tuple unpacking or another complex assignment target, Pyflakes must not raise an internal exception.
- Such a binding is not a valid `__all__` export declaration and must not suppress warnings for otherwise-unused imports. No separate diagnostic for the invalid declaration is required.
