tatsu.ast.AST objects don't pickle/unpickle properly
Observe:

```
>>> from tatsu.ast import AST
>>> a=AST(parseinfo=('Some parseinfo'))
>>> a
{'parseinfo': 'Some parseinfo'}
>>> import pickle
>>> pickle.loads(pickle.dumps(a))
{'parseinfo_': 'Some parseinfo'}
```

Note that after pickling/unpickling, the AST object is different.

[HIDDEN]

### Additional contract requirements

- Pickling and then unpickling an `AST` must preserve its key/value contents. The resulting object must compare equal to the original and retain entries such as `parseinfo`.
