auto_exc's hashing behavior and its documentation do not match
The [documentation](https://github.com/python-attrs/attrs/blob/25a02bbc7b5309acebda20101125372d42c978db/src/attr/_make.py#L846) for `auto_exc` says:
```
  - the values for *cmp* and *hash* are ignored and the instances compare
          and hash by the instance's ids (N.B. ``attrs`` will *not* remove
          existing implementations of ``__hash__`` or the equality methods. It
          just won't add own ones.),
```

However, the test for `auto_exc` [says](https://github.com/python-attrs/attrs/blob/25a02bbc7b5309acebda20101125372d42c978db/tests/test_dark_magic.py#L519):
```
    Classes with auto_exc=True have a Exception-style __str__, are neither
        comparable nor hashable, and store the fields additionally in
        self.args.
```

and [tests](https://github.com/python-attrs/attrs/blob/25a02bbc7b5309acebda20101125372d42c978db/tests/test_dark_magic.py#L558):

```
            with pytest.raises(TypeError):
                hash(e)
```

The documentation and the code should be made consistent.  I noticed this because `unittest` complained that the exception type was unhashable when thrown from a test and I see some [references to `logging` expecting hashable exceptions](https://github.com/schematics/schematics/issues/452), so the documented behavior is probably better than the implemented behavior.
