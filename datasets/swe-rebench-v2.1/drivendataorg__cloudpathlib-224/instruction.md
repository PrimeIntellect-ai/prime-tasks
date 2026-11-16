Cannot pickle path objects
```python
Python 3.9.12 (main, Apr  5 2022, 06:56:58)
[GCC 7.5.0] :: Anaconda, Inc. on linux
>>> import pickle
>>> pickle.format_version
'4.0'
>>> import cloudpathlib
>>> cloudpathlib.__version__
'0.7.1'
>>> with open("/home/matthew/s3.pkl", "w") as f:
...     pickle.dump(cloudpathlib.S3Path("s3://bucket/key"), f)
...
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
AttributeError: Can't pickle local object 'lazy_call.<locals>._handler'
```

`pickle` docs: [What can be pickled and unpickled?](https://docs.python.org/3/library/pickle.html#what-can-be-pickled-and-unpickled)

### Additional contract requirements

- When a cloud path is unpickled, it must use the default client for its path class, retain the same string representation, and support a successful `exists()` call.
