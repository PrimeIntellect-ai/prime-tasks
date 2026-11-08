Overloading the `__pow__` method in Electron class
Something as simple as the following would fail to dispatch right now because Electron class doesn't have the `__pow__` method defined similar to `__add__`, `__mul__`, etc.. Adding that would solve the issue.

```python
@ct.electron
def g(x):
    return 42 * x

@ct.lattice
def workflow(x):
    res = g(x)
    return res ** 2
```
