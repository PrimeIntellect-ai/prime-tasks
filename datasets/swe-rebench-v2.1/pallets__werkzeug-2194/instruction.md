to_dict method on CombinedMultiDict doesn't give combined result for overlapping keys
Whenever I call `to_dict(flat=False)` on a `CombinedMultiDict`, obtained from combining two MultiDicts with overlapping keys, only the values of the last MultiDict are returned.

```python
# altered from documentation to make keys overlapping.
from werkzeug.datastructures import CombinedMultiDict, MultiDict
post = MultiDict([('foo', 'bar'),('foo', 'bar2')])
get = MultiDict([('foo', 'bar3')])
combined = CombinedMultiDict([get, post])
combined.getlist('foo')
>> ['bar3', 'bar', 'bar2']
combined.to_dict(flat=False)
>> {'foo': ['bar3']}
```

From a class that intends to combine two MultiDicts, I expect the result from one of its methods to be a combined result.
Environment:
- Python version: 3.6.8
- Werkzeug version: 1.0.1
