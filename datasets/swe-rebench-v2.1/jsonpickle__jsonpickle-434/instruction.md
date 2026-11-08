Numpy handlers does not handle views correctly
When using the numpy handler, some classes cannot be serialized. One example is the LogisticRegression class in scikit-learn>=0.24:

[the following example uses scikit-learn==0.24 and the latest jsonpickle==3.0.1, although previous versions of jsonpickle have the same issue as well]

```python
import sklearn.datasets
from sklearn.linear_model import LogisticRegression
import jsonpickle

from jsonpickle.ext.numpy import register_handlers

register_handlers()


iris = sklearn.datasets.load_iris()
X = iris.data[:, :2]
y = (iris.target != 0) * 1

pipe = LogisticRegression(solver="lbfgs")

pipe.fit(X, y)

res = pipe.predict(X)

# Try serializing/deserializing
js = jsonpickle.dumps(pipe)

pipe2 = jsonpickle.loads(js)
```
This fails with the following error:
```
...
File ~/miniconda3/envs/dstools/lib/python3.8/site-packages/jsonpickle/ext/numpy.py:328, in NumpyNDArrayHandlerView.restore(self, data)
    324 else:
    325     # decode array view, which references the data of another array
    326     base = self.context.restore(base, reset=False)
    327     assert (
--> 328         base.flags.forc
    329     ), "Current implementation assumes base is C or F contiguous"
    331     arr = np.ndarray(
    332         buffer=base.data,
    333         dtype=self.restore_dtype(data).newbyteorder(data.get('byteorder', '|')),
   (...)
    336         strides=data.get('strides', None),
    337     )
    339     self.restore_flags(data, arr)

AttributeError: 'list' object has no attribute 'flags'
```

NOTE: if I do NOT use the numpy extension, i.e., if I comment the following lines:

```
# from jsonpickle.ext.numpy import register_handlers

# register_handlers()
```
then everything works. This seems to point to a specific issue with the numpy handler.
