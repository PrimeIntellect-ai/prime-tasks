False positive of undefined name `__class__` when running `tidy-imports`
Given the following file:
```python
# a.py
class MyClass:
    def get_class(self):
        return __class__
```

When running

```bash
tidy-imports --replace a.py
```

I got the following error

```
[PYFLYBY] /home/nixos/peftai/a.py:4: undefined name '__class__' and no known import for it
```

I think the error message is a false positive.

### Version information
```bash
tidy-imports --version
```
```
pyflyby 1.9.2 (tidy-imports)
```

### Additional contract requirements

An otherwise unbound reference to `__class__` outside a class method must still be reported as undefined.
