Type-annotated "encoding" field crashes isort
This came up while trying to enforce isort imports in [typeshed](/python/typeshed). Please consider the following file:

```python
class X:
    encoding: str
```

(The actual file it stumbles over is [stdlib/3/io.pyi](https://github.com/python/typeshed/blob/master/stdlib/3/io.pyi).)

Running isort 4.3.21 with Python 3.7 against this fails with the following traceback:

```
Traceback (most recent call last):
  File "./.venv/bin/isort", line 10, in <module>
    sys.exit(main())
  File "/home/srittau/.venv/lib/python3.7/site-packages/isort/main.py", line 379, in main
    for sort_attempt in attempt_iterator:
  File "/home/srittau/.venv/lib/python3.7/site-packages/isort/main.py", line 377, in <genexpr>
    attempt_iterator = (sort_imports(file_name, **arguments) for file_name in file_names)
  File "/home/srittau/.venv/lib/python3.7/site-packages/isort/main.py", line 88, in sort_imports
    result = SortImports(file_name, **arguments)
  File "/home/srittau/.venv/lib/python3.7/site-packages/isort/isort.py", line 114, in __init__
    with io.open(file_path, encoding=file_encoding, newline='') as file_to_import_sort:
LookupError: unknown encoding: str
```

### Additional contract requirements

- A file encoding declaration is recognized only when it appears in a comment on one of the first two lines; a declaration on line 3 must be ignored.
