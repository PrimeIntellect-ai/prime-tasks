ETSConfig attributes can't be deleted
Most of the interesting `ETSConfig` attributes are exposed as properties wrapping a hidden private field. Those properties have getters and setters but no deleters.

The missing deleters cause issues when trying to mock `ETSConfig` attributes, which would otherwise be a reasonable pattern for making temporary changes to those attributes:

```python
>>> from traits.etsconfig.api import ETSConfig
>>> ETSConfig.application_home
'/Users/mdickinson/.enthought/'
>>> import unittest.mock
>>> with unittest.mock.patch.object(ETSConfig, "application_home", new="/Users/mdickinson/.something_else"):
...     print(ETSConfig.application_home)
...
/Users/mdickinson/.something_else
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/opt/local/Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/unittest/mock.py", line 1567, in __exit__
    delattr(self.target, self.attribute)
AttributeError: can't delete attribute 'application_home'
>>> ETSConfig.application_home
'/Users/mdickinson/.something_else'
```

It ought to be fairly easy to add meaningful attribute deleters, so that the mock pattern works.
