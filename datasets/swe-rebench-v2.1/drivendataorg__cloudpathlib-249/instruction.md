Module fails to import when Python is ran with -OO
Since `-OO` removes docstrings, the module fails on import as shown in the following trace:

```python
[...]
    from cloudpathlib import AnyPath, CloudPath
  File "/home/javier/.virtualenvs/WebsiteTopicClassifier/lib/python3.6/site-packages/cloudpathlib/__init__.py", line 3, in <module>
    from .anypath import AnyPath
  File "/home/javier/.virtualenvs/WebsiteTopicClassifier/lib/python3.6/site-packages/cloudpathlib/anypath.py", line 5, in <module>
    from .cloudpath import InvalidPrefixError, CloudPath
  File "/home/javier/.virtualenvs/WebsiteTopicClassifier/lib/python3.6/site-packages/cloudpathlib/cloudpath.py", line 136, in <module>
    class CloudPath(metaclass=CloudPathMeta):
  File "/home/javier/.virtualenvs/WebsiteTopicClassifier/lib/python3.6/site-packages/cloudpathlib/cloudpath.py", line 127, in __init__
    [HIDDEN]
TypeError: unsupported operand type(s) for +: 'NoneType' and 'str'
```
