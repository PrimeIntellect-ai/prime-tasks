TypeError when calling a pickled + unpickled function in __main__ with keyword-only argument
```py
import cloudpickle

def func_with_kw_only_args(a, *, b=1):
    return a + b


new_func = cloudpickle.loads(cloudpickle.dumps(func_with_kw_only_args))
new_func(1)
```

Error:
```
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-18-ee6063f05eec> in <module>
      6
      7 new_func = cloudpickle.loads(cloudpickle.dumps(func_with_kw_only_args))
----> 8 new_func(1)
      9
     10

TypeError: func_with_kw_only_args() missing 1 required keyword-only argument: 'b'
```

Original bug was seen in joblib: https://github.com/joblib/joblib/issues/863

Note: there is no error when putting the function with keyword-only arguments in a Python module.
