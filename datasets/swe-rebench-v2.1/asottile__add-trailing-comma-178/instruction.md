`AssertionError: Past end?` on match statement
System info:
- Python 3.10.4

Pre-Commit config:
```
repos:
- repo: https://github.com/asottile/add-trailing-comma
  rev: v2.2.1
  hooks:
  - id: add-trailing-comma
```

Minimum breaking example
```python
a = 'a'
b = 'b'

match a, b:
    case 'a', _:
        print('a')
```

The above code causes a break when running pre-commit hooks even though it is syntactically valid:

> root@fed07c6390e1:/exos# pre-commit run add-trailing-comma --files mwe.py
> Add trailing commas......................................................Failed
>   hook id: add-trailing-comma
>   exit code: 1
> Traceback (most recent call last):
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/bin/add-trailing-comma", line 8, in <module>
>     sys.exit(main())
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/lib/python3.10/site-packages/add_trailing_comma/_main.py", line 102, in main
>     ret |= fix_file(filename, args)
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/lib/python3.10/site-packages/add_trailing_comma/_main.py", line 71, in fix_file
>     contents_text = _fix_src(contents_text, args.min_version)
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/lib/python3.10/site-packages/add_trailing_comma/_main.py", line 45, in _fix_src
>     callback(i, tokens)
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/lib/python3.10/site-packages/add_trailing_comma/_plugins/match.py", line 57, in _fix_sequence
>     find_simple(i, tokens),
>   File "/root/.cache/pre-commit/repo57gmvexh/py_env-python3.10/lib/python3.10/site-packages/add_trailing_comma/_token_helpers.py", line 43, in find_simple
>     raise AssertionError('Past end?')
> AssertionError: Past end?

However if I add parens around the case in the match statement there is no break

```python
a = 'a'
b = 'b'

match a, b:
    case ('a', _):
        print('a')
```

> root@fed07c6390e1:/exos# pre-commit run add-trailing-comma --files mwe.py
> Add trailing commas......................................................Passed

The original example passes for `==2.1.0` but breaks on `>=2.2.0`

### Additional contract requirements

- When `_fix_src` is called with `min_version=(2, 7)` on `match x:\n    case 1, 2:\n        pass\n`, it must return the input string unchanged.
