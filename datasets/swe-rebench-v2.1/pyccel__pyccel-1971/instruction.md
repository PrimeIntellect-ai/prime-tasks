Missing error when passing the wrong type to an optional argument
### Describe the bug
When the wrong type is passed as an optional argument the wrapper checks the types without raising an error. This results in a system error from Python

### To Reproduce
Provide code to reproduce the behavior:
```python
def f(y  : 'int' =  None):
    if y is None:
        return 2
    else:
        return y
```
```python
from tmp_optional import f

f(4.0)
```

### Error details
Provide the generated code, or the error message:
```
Traceback (most recent call last):
  File "/home/emily/Code/pyccel/tests/test.py", line 3, in <module>
    f(4.0)
SystemError: <built-in function f> returned NULL without setting an exception
```

### Expected behavior
The error should be raised as for non-optionals:
```
Traceback (most recent call last):
  File "/home/emily/Code/pyccel/tests/test.py", line 3, in <module>
    f(4.0)
TypeError: Expected an argument of type int for argument y
```

### Language
Fortran/C

### Additional context
Fixing this may result in the error seen in #1963
