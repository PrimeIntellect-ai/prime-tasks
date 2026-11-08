additional_skip_names is ignored for Path().open
**Describe the bug**
I noticed `additional_skip_names` works for builtin `open`, `io.open` and `os.open` but it doesn't work for `Path().open` unless I add `pathlib` to `additional_skip_names` too. I guess it is because `Path.open` itself is not monitored and `io.open` is monitored instead as `Path.open` uses `io.open` internally.

**How To Reproduce**

This works:

```python
with Patcher(
    additional_skip_names=[
        'pathlib',
    ],
) as patcher:
    if patcher.fs:
      from x import x
      x()
```

x.py
```python
def x():
  print(Path('some_path').open('r').read())
```

But this doesn't work:

```python
with Patcher(
    additional_skip_names=[
        'x',
    ],
) as patcher:
    if patcher.fs:
      from x import x
      x()
```

x.py
```python
def x():
  print(Path('some_path').open('r').read())
```

**Your environment**
macOS-14.4.1-arm64-arm-64bit
Python 3.11.9 (main, Apr  2 2024, 08:25:04) [Clang 15.0.0 (clang-1500.3.9.4)]
pyfakefs 5.4.1
pytest 8.2.0
