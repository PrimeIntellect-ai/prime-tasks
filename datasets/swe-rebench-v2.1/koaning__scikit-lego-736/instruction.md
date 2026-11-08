[BUG] Can't load a pickled DebugPipeline with a custom log_callback
Hi,

when I try to load a previously fitted and pickled `DebugPipeline` instance that uses a custom `log_callback` from a pickle file I get the following error:

```python
AttributeError: 'Memory' object has no attribute '_'
```

Here's a simple snippet to reproduce the error (tested on Google Colab with `sklego==0.9.4`)
```python
import joblib
import logging
from sklego.pipeline import make_debug_pipeline, default_log_callback
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LinearRegression
from sklearn.datasets import make_regression

X, y = make_regression()
pipeline = make_debug_pipeline(StandardScaler(), LinearRegression(), log_callback=default_log_callback)
pipeline.fit(X, y)

joblib.dump(pipeline, './pipeline.pkl')
joblib.load('./pipeline.pkl')
```

Which returns the following stack trace:
```python
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
[<ipython-input-13-7ed979951525>](https://localhost:8080/#) in <cell line: 0>()
     11
     12 joblib.dump(pipeline, './pipeline.pkl')
---> 13 joblib.load('./pipeline.pkl')

[/usr/local/lib/python3.11/dist-packages/joblib/numpy_pickle.py](https://localhost:8080/#) in load(filename, mmap_mode)
    656                     return load_compatibility(fobj)
    657
--> 658                 obj = _unpickle(fobj, filename, mmap_mode)
    659     return obj

[/usr/local/lib/python3.11/dist-packages/joblib/numpy_pickle.py](https://localhost:8080/#) in _unpickle(fobj, filename, mmap_mode)
    575     obj = None
    576     try:
--> 577         obj = unpickler.load()
    578         if unpickler.compat_mode:
    579             warnings.warn("The file '%s' has been generated with a "

[/usr/lib/python3.11/pickle.py](https://localhost:8080/#) in load(self)
   1211                     raise EOFError
   1212                 assert isinstance(key, bytes_types)
-> 1213                 dispatch[key[0]](self)
   1214         except _Stop as stopinst:
   1215             return stopinst.value

[/usr/lib/python3.11/pickle.py](https://localhost:8080/#) in load_reduce(self)
   1588         args = stack.pop()
   1589         func = stack[-1]
-> 1590         stack[-1] = func(*args)
   1591     dispatch[REDUCE[0]] = load_reduce
   1592

AttributeError: 'Memory' object has no attribute '_'
```

### Additional contract requirements

- `sklego.pipeline` provides the module-level function `make_debug_pipeline(*steps, log_callback=None, **kwargs)`. It builds a `DebugPipeline` from the given estimators, forwards `log_callback` to the pipeline, and forwards any other keyword arguments to the `DebugPipeline` constructor.
- `sklego.pipeline` provides the module-level function `default_log_callback(output, execution_time, **kwargs)`, which emits an INFO-level log message for a pipeline step.
- A fitted `DebugPipeline` that was configured with a log callback (either `default_log_callback` or a user-supplied callable) can be written with `joblib.dump` and read back with `joblib.load` without raising an error.
- The restored fitted pipeline can still be used to make predictions.
- After it has been restored, running the pipeline keeps invoking the configured log callback, so a user-supplied callback continues to produce its own log output.
