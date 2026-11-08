On Python 3, __class__ can be used without self
*Original report by [icordasc](https://launchpad.net/~icordasc) (@sigmavirus24?) on [Launchpad](https://bugs.launchpad.net/bugs/1487725):*

------------------------------------

On Python 3, the following code raises a warning:

```python
class Test(object):
    def __init__(self):
        print(__class__.__name__)
        self.x = 1

t = Test()
```

This is actually valid Python 3 code, but PyFlakes doesn't quite understand that:

    test.py:3: undefined name '__class__'
