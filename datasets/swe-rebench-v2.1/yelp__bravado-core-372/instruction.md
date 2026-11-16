Add pickle support to bravado_core.spec.Spec
Currently `Spec` is not pickable
```
>>> import pickle
>>> from bravado_core.spec import Spec
>>> spec_dict = {
...   "swagger": "2.0",
...   "info": {
...     "title": "Test",
...     "version": "1.0"
...   },
...   "paths": {},
...   "definitions": {}
... }
>>> pickle.dumps(Spec.from_dict(spec_dict))
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
AttributeError: Can't pickle local object 'build_http_handlers.<locals>.download'
>>>
```

This prevents libraries to use `Spec` instances across processes or just to pickle clients.
