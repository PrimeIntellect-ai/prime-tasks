Issues when deserializing `numpy.poly1d`
I want to transfer an object containing a `numpy.poly1d` property using jsonpickle. Is this something that could be enabled by `jsonpickle` and its numpy extension or is the recommended way to treat this within `__getstate__` and `__setstate__`?

Either way, I would have expected that unsupported attributes (like `numpy.poly1d` seems to be) would be stripped during serialization, so that they cannot cause issues during deserialization.

The serialized data and the traceback I am getting:

```json
{"command": "echo", "args": {"obj": {"py/object": "numpy.poly1d", "coeffs": {"py/object": "numpy.ndarray", "base": {"py/object": "numpy.ndarray", "dtype": "int64", "values": [1, 2, 3]}, "shape": [3], "dtype": "int64", "values": [1, 2, 3]}, "_variable": "x"}}}
```

```python-traceback
deserializing numpy.poly1d (__init__.py:24)
deserializing numpy.ndarray (__init__.py:24)
deserializing numpy.ndarray (__init__.py:24)
----------------------------------------
Exception occurred during processing of request from ('127.0.0.1', 56792)
Traceback (most recent call last):
  File "/Users/mkj/.pyenv/versions/3.10.2/lib/python3.10/socketserver.py", line 316, in _handle_request_noblock
    self.process_request(request, client_address)
  File "/Users/mkj/.pyenv/versions/3.10.2/lib/python3.10/socketserver.py", line 347, in process_request
    self.finish_request(request, client_address)
  File "/Users/mkj/.pyenv/versions/3.10.2/lib/python3.10/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/Users/mkj/.pyenv/versions/3.10.2/lib/python3.10/socketserver.py", line 747, in __init__
    self.handle()
  File "../server.py", line 40, in handle
    request = jsonpickle.decode(data)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 85, in decode
    return context.restore(data, reset=reset, classes=classes)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 355, in restore
    value = self._restore(obj)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 337, in _restore
    return restore(obj)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 808, in _restore_dict
    data[k] = self._restore(v)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 337, in _restore
    return restore(obj)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 808, in _restore_dict
    data[k] = self._restore(v)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 337, in _restore
    return restore(obj)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 756, in _restore_object
    return self._restore_object_instance(obj, cls, class_name)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 732, in _restore_object_instance
    instance = self._restore_object_instance_variables(obj, instance)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 666, in _restore_object_instance_variables
    instance = self._restore_from_dict(obj, instance)
  File "../python3.10/site-packages/jsonpickle/unpickler.py", line 617, in _restore_from_dict
    setattr(instance, k, value)
  File "../python3.10/site-packages/numpy/lib/polynomial.py", line 1193, in coeffs
    if value is not self._coeffs:
  File "../python3.10/site-packages/numpy/lib/polynomial.py", line 1216, in _coeffs
    return self.__dict__['coeffs']
KeyError: 'coeffs'
----------------------------------------
```
