failed to pickle objects inherited from __slots__ in 1.2.2
My first test program is
```
class Base(object):
    __slots__ = []

class Inherited(Base):
    def __init__(self, v):
        self.v = v

import cloudpickle

a = Inherited(1)
with open("pickle", "wb") as f:
    cloudpickle.dump(a, f)
```
And then I read the pickle file with
```
import cloudpickle

with open("pickle", "rb") as f:
    cloudpickle.load(f)
```

When I run this with Python 3 and cloudpickle 1.2.2, it gives me error
```
Traceback (most recent call last):
  File "algo/code2.py", line 4, in <module>
    cloudpickle.load(f)
AttributeError: 'Inherited' object has no attribute '__dict__'
```

But this runs fine under Python 2 and cloudpickle 0.5.3
