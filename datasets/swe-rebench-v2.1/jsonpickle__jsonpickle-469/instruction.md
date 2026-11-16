Decoding datetime with tzinfo raises TypeError
#### Python Version: 3.10.12

#### jsonpickle Version: 1.2

jsonpickle.decode function is raising `TypeError: 'NoneType' object is not callable` when pass some pickled object containing an datetime object with tzinfo.

datetime object without tzinfo works fine.

``` py
Python 3.10.12 (main, Jun  7 2023, 19:08:47) [GCC 9.4.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> from datetime import datetime
>>> from zoneinfo import ZoneInfo
>>> import jsonpickle
>>>
>>> SaoPaulo = ZoneInfo('America/Sao_Paulo')
>>>
>>> USEastern = ZoneInfo('US/Eastern')
>>>
>>> now = datetime.now()
>>> now
datetime.datetime(2023, 6, 8, 15, 27, 1, 305282)
>>>
>>> now_sp = now.replace(tzinfo=SaoPaulo)
>>> now_us = now.replace(tzinfo=USEastern)
>>>
>>> pickled_now_sp = jsonpickle.encode(now_sp)
>>> pickled_now_us = jsonpickle.encode(now_us)
>>> pickled_now = jsonpickle.encode(now)
>>>
>>> unpickled_now = jsonpickle.decode(pickled_now) # This works fine
>>> unpickled_now
datetime.datetime(2023, 6, 8, 15, 27, 1, 305282)
>>>
>>> unpickled_now_sp = jsonpickle.decode(pickled_now_sp) # This raise an error
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 41, in decode
    return context.restore(data, reset=reset, classes=classes)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 150, in restore
    value = self._restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 207, in _restore
    return restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 315, in _restore_object
    instance = handler(self).restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/handlers.py", line 170, in restore
    params = (value,) + tuple([restore(i, reset=False) for i in args[1:]])
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/handlers.py", line 170, in <listcomp>
    params = (value,) + tuple([restore(i, reset=False) for i in args[1:]])
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 150, in restore
    value = self._restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 207, in _restore
    return restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 242, in _restore_reduce
    stage1 = f(*args)
TypeError: 'NoneType' object is not callable
>>>
>>>
>>> unpickled_now_us = jsonpickle.decode(pickled_now_us) # diferent tz also raises the same error
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 41, in decode
    return context.restore(data, reset=reset, classes=classes)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 150, in restore
    value = self._restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 207, in _restore
    return restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 315, in _restore_object
    instance = handler(self).restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/handlers.py", line 170, in restore
    params = (value,) + tuple([restore(i, reset=False) for i in args[1:]])
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/handlers.py", line 170, in <listcomp>
    params = (value,) + tuple([restore(i, reset=False) for i in args[1:]])
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 150, in restore
    value = self._restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 207, in _restore
    return restore(obj)
  File "/usr/local/python/3.10.12/lib/python3.10/site-packages/jsonpickle/unpickler.py", line 242, in _restore_reduce
    stage1 = f(*args)
TypeError: 'NoneType' object is not callable
```
