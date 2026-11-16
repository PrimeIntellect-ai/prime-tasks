Failure on unhashable functions in Python 2

This showed up in Dask's test suite after the recent release.  Python 2 only.

```python
In [1]: d = {'a': 1}

In [2]: import cloudpickle

In [3]: cloudpickle.dumps(d.get)
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-3-8adaadeed8cc> in <module>()
----> 1 cloudpickle.dumps(d.get)

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/site-packages/cloudpickle/cloudpickle.pyc in dumps(obj, protocol)
    844     try:
    845         cp = CloudPickler(file,protocol)
--> 846         cp.dump(obj)
    847         return file.getvalue()
    848     finally:

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/site-packages/cloudpickle/cloudpickle.pyc in dump(self, obj)
    258         self.inject_addons()
    259         try:
--> 260             return Pickler.dump(self, obj)
    261         except RuntimeError as e:
    262             if 'recursion' in e.args[0]:

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/pickle.pyc in dump(self, obj)
    222         if self.proto >= 2:
    223             self.write(PROTO + chr(self.proto))
--> 224         self.save(obj)
    225         self.write(STOP)
    226

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/pickle.pyc in save(self, obj)
    284         f = self.dispatch.get(t)
    285         if f:
--> 286             f(self, obj) # Call unbound method with explicit self
    287             return
    288

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/site-packages/cloudpickle/cloudpickle.pyc in save_builtin_function(self, obj)
    611         if obj.__module__ == "__builtin__":
    612             return self.save_global(obj)
--> 613         return self.save_function(obj)
    614     dispatch[types.BuiltinFunctionType] = save_builtin_function
    615

/home/mrocklin/Software/anaconda/envs/27/lib/python2.7/site-packages/cloudpickle/cloudpickle.pyc in save_function(self, obj, name)
    330         interactive prompt, etc) and handles the pickling appropriately.
    331         """
[HIDDEN]
    333             # We keep a special-cased cache of built-in type constructors at
    334             # global scope, because these functions are structured very

TypeError: unhashable type: 'dict'
```

### Additional contract requirements

- On Python 2, cloudpickle must serialize and deserialize unhashable built-in methods such as `d.get`. The resulting method must remain callable and preserve its lookup behavior: for `d = {'a': 1}`, it returns `1` for `'a'` and `None` for a missing key.
