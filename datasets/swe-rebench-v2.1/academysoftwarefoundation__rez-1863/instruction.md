Bake resolves with rez<3.2.0 can't be loaded due to missing `testing` key
Baked resolves generated with older versions are not compatible with rez-3.2.0.
Note a regression per say but a breaking change

**Environment**
* windows 10
* 3.2.0
* Python 3.11.4

**To Reproduce**
1. using rez-3.0.0, bake a simple resolve into a rxt file
```
> rez --version
Rez 3.0.0 from c:\rez\3.0.0\Lib\site-packages\rez (python 3.11)
> rez env python --output py.rxt
```

2. using rez-3.2.0, resolve a context from the above rxt file
```
> rez env --input py.rxt
12:10:10 ERROR    ResolvedContextError: Failed to load context from py.rxt: KeyError: 'testing'
```

**Expected behavior**
We should be left in a resolved context

**Actual behavior**
Resolution failure.

**Related Issues/PRs**
* #1740

### Additional contract requirements

- `ResolvedContext.load(context_path)` returns a `ResolvedContext` object populated with the data read from the serialized context file.
- A context loaded from serialized data that does not contain a `testing` flag has its `testing` flag default to `False`.
