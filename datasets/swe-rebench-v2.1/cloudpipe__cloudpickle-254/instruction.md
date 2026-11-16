__name__ being lost inside cloudpickled staticmethods? (0.8.0 regression)
Not sure if this is expected or not?  Reproducer below.

Thanks!
Tim

----

Output with cloudpickle 0.7.0:

```
(cp7) $ python reproducer.py
<pkg.mymod2.MyClass object at 0x7fbf18b3d828>
```

cloudpickle 0.8.0:

```python-traceback
(cp8) $ python reproducer.py
Traceback (most recent call last):
  File "reproducer.py", line 7, in <module>
    print(f())
  File "/mypath/pkg/mymod.py", line 4, in func
    from .mymod2 import MyClass
KeyError: "'__name__' not in globals"
```

```
pkg/
   __init__.py
   mymod.py
   mymod2.py
reproducer.py
```

```python
# pkg/__init__.py
# blank
```

```python
# pkg/mymod.py
class Blah(object):
    @staticmethod
    def func():
        from .mymod2 import MyClass
        return MyClass()
```

```python
# pkg/mymod2.py
class MyClass(object):
    pass
```

```python
# reproducer.py
from pkg.mymod import Blah
from cloudpickle import dumps
from pickle import loads

f = loads(dumps(Blah.func))

print(f())
```
