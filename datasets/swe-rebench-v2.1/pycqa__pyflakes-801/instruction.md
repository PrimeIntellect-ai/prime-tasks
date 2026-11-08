False Positive: walrus in a list comprehension
Minimal reproduction:

```python
def foo(x):
    fns = [lambda x: x + 1, lambda x: x + 2, lambda x: x + 3]
    return [(x := fn(x)) for fn in fns]
```

This raises F841 incorrectly asserting that the `x` variable assigned in the comprehension is never used
