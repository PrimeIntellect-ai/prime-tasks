Detect and use docstrings set after-the-fact.
Twisted has some code that does something like

``` python
if _PY3:
   def func(args):
       pass
else:
    def func(args):
        pass

func.__doc__ = """
func does some stuff.
```

to avoid duplicating a docstring. Unfortunately, pydoctor doesn't pick this up, so it appears that `func` is undocumented.

### Additional contract requirements

- For invalid `__doc__` assignments, emit these diagnostics to standard output in source order, with exactly this output for the tested case (including the final newline):

```text
<unknown>:20: Unable to figure out target for __doc__ assignment
<unknown>:21: Unable to figure out target for __doc__ assignment: computed full name not found: real
<unknown>:22: Unable to figure out value for __doc__ assignment, maybe too complex
<unknown>:23: Ignoring value assigned to __doc__: not a string
```

- If a non-string value is assigned to an object’s `__doc__`, ignore that value and leave any existing docstring unchanged.
