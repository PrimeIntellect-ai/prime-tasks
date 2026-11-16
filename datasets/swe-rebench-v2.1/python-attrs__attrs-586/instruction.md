Couldn't use numpy arrays as defaults on attrs 19.2
The following code stops working when upgrading from attrs 19.1 to 19.2:

```
@attr.s(auto_attribs=True)
class NumParams:
    N = 3
    alpha = np.zeros((N, Ng))
```

Seems that change #556 requires that default attributes should implement `__eq__`, which is not the case for numpy arrays.

Taceback is:
```
    @attr.s(auto_attribs=True)
../../../../miniconda/envs/attests/lib/python3.6/site-packages/attr/_make.py:1010: in wrap
    return builder.build_class()
../../../../miniconda/envs/attests/lib/python3.6/site-packages/attr/_make.py:498: in build_class
    return self._patch_original_class()
[HIDDEN]
    [HIDDEN]
E   ValueError: The truth value of an array with more than one element is ambiguous. Use a.any() or a.all()
```

### Additional contract requirements

- An `auto_attribs=True` class must accept a NumPy-array default whose equality comparison cannot be used as a boolean, without failing during class creation.
