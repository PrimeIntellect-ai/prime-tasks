Unable to pickle itertools.chain.from_iterable
Using cloudpickle as cloned from the repo just now, Python 2.7.11:

```{python}
Python 2.7.11 (default, Mar  4 2016, 11:10:11)
[GCC 4.2.1 Compatible Apple LLVM 7.0.2 (clang-700.1.81)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> import cloudpickle
>>> import itertools
>>> cloudpickle.dumps(itertools.chain.from_iterable)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "cloudpickle/cloudpickle.py", line 629, in dumps
    cp.dump(obj)
  File "cloudpickle/cloudpickle.py", line 107, in dump
    return Pickler.dump(self, obj)
  File "/usr/local/Cellar/python/2.7.11/Frameworks/Python.framework/Versions/2.7/lib/python2.7/pickle.py", line 224, in dump
    self.save(obj)
  File "/usr/local/Cellar/python/2.7.11/Frameworks/Python.framework/Versions/2.7/lib/python2.7/pickle.py", line 286, in save
    f(self, obj) # Call unbound method with explicit self
  File "cloudpickle/cloudpickle.py", line 330, in save_builtin_function
    return self.save_function(obj)
  File "cloudpickle/cloudpickle.py", line 203, in save_function
    or getattr(obj.__code__, 'co_filename', None) == '<stdin>'
AttributeError: 'builtin_function_or_method' object has no attribute '__code__'
```

I get the same result on Python 3.5.1.
