init unique_filename is problematic for exception aggregation
We had a case where a custom converter was often failing due to an app issue.  The traceback will include a line with a unique ID based on the initial attr values in the class:

```
File "<attrs generated init 81db48c8801f50d1c320ad1b8d1e0028320432b2>", line 3, in __init__
```

Having a unique ID in the traceback in turn causes problems for exception fingerprinting (e.g. by Sentry).  I'm not thrilled about doing custom traceback filtering for such cases, and would like to explore other options.

I wonder what the full rationale is for ensuring the unique filename, and whether it could be made optional.

Including a hash of the attribute values is essentially like dumping the values of all attributes of a class instance as part of the traceback whenever there is a constructor error regarding a single attribute-- which is less than precise error reporting.

https://github.com/python-attrs/attrs/blob/dc1b5a01e98a9ba49d45ad07ba6ae0ee2d9c1b8e/src/attr/_make.py#L1268

### Additional contract requirements

Generated `__init__` filenames for an equivalent attrs class definition must be stable across separate process starts, even when attribute definitions have representations that vary between processes (such as a lambda default). Such instability should not introduce avoidable differences into exception fingerprints.
