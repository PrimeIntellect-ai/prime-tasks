The underscore_attrs_are_private config flag turns __doc__ attribute into a ModelPrivateAttr
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.7.2
            pydantic compiled: False
                 install path: D:\dev\Miniconda3\envs\geoenv\Lib\site-packages\pydantic
               python version: 3.8.6 | packaged by conda-forge | (default, Oct  7 2020, 18:22:52) [MSC v.1916 64 bit (AMD64)]
                     platform: Windows-10-10.0.19041-SP0
     optional deps. installed: ['typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

Pydantic v1.7 introduced the private attributes. But when the config flag `underscore_attrs_are_private` is set to `True`, the model's `__doc__` attribute also becomes a private attribute. Example:

```py
>>> from pydantic import BaseModel
>>> class MyModel(BaseModel):
...     """MyModel docsting."""
...     class Config:
...         underscore_attrs_are_private = True
...
>>> MyModel.__doc__
<member '__doc__' of 'MyModel' objects>
```

My current workaround is to define a new metaclass to handle the issue:
```py
>>> from pydantic import BaseModel
>>> from pydantic.main import ModelMetaclass
>>> from pydantic.fields import ModelPrivateAttr
[HIDDEN]
>>> class MyModel(BaseModel, metaclass=DocPreservingModelMetaclass):
...     """MyModel docsting."""
...     class Config:
...         underscore_attrs_are_private = True
...
>>> MyModel.__doc__
'MyModel docsting.'
```

[HIDDEN]
