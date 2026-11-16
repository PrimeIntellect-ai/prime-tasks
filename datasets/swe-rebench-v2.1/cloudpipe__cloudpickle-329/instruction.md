Cannot pickle properties with python 3.8
Hello,

The following code, which uses joblib with cloudpickle backend, crashes with python 3.8.1, but works with python 3.7.4. Can you fix it?

Thanks

Python code:
```python
import joblib as jl

class Test:
    def __init__(self, a):
        self._a = a

    @property
    def a(self):
        return self._a


def jlcb(x):
    Test(x).a

jl.Parallel(n_jobs=-1)(jl.delayed(jlcb)(z) for z in range(100))
```

Exception with python 3.8.1 (paths partially replaced with "#########")
```text
joblib.externals.loky.process_executor._RemoteTraceback:
"""
Traceback (most recent call last):
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/externals/loky/backend/queues.py", line 150, in _feed
    obj_ = dumps(obj, reducers=reducers)
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/externals/loky/backend/reduction.py", line 247, in dumps
    dump(obj, buf, reducers=reducers, protocol=protocol)
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/externals/loky/backend/reduction.py", line 240, in dump
    _LokyPickler(file, reducers=reducers, protocol=protocol).dump(obj)
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/externals/cloudpickle/cloudpickle_fast.py", line 538, in dump
    return Pickler.dump(self, obj)
TypeError: cannot pickle 'property' object
"""

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "../demo_joblib.py", line 15, in <module>
    jl.Parallel(n_jobs=-1)(jl.delayed(jlcb)(z) for z in range(100))
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/parallel.py", line 1017, in __call__
    self.retrieve()
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/parallel.py", line 909, in retrieve
    self._output.extend(job.get(timeout=self.timeout))
  File "#########/.local/share/virtualenvs/3.8-tCZLdKH5/lib/python3.8/site-packages/joblib/_parallel_backends.py", line 562, in wrap_future_result
    return future.result(timeout=timeout)
  File "/opt/python/3.8.1/lib/python3.8/concurrent/futures/_base.py", line 439, in result
    return self.__get_result()
  File "/opt/python/3.8.1/lib/python3.8/concurrent/futures/_base.py", line 388, in __get_result
    raise self._exception
_pickle.PicklingError: Could not pickle the task to send it to the workers.
```
