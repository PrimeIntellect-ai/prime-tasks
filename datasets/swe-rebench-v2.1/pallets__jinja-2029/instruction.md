Cannot pickle `jinja2.utils.missing`
The `jinja2.utils.missing` singleton instance cannot be pickled since pickle cannot find `MissingType` due to the `jinja2.utils.MissingType` attribute not existing:

```python
import pickle
import jinja2.utils

pickle.dumps(jinja2.utils.missing)
```

Running the above code results in the following error:

```
Traceback (most recent call last):
  File "/tmp/bug.py", line 4, in <module>
    pickle.dumps(jinja2.utils.missing)
_pickle.PicklingError: Can't pickle <class 'jinja2.utils.MissingType'>: attribute lookup MissingType on jinja2.utils failed
```

Attempting to pickle (and then restore) the `jinja2.utils.missing` singleton instance should succeed. Supporting this would allow pickling of `jinja2.runtime.Undefined` instances which do not set `obj`, once https://github.com/pallets/jinja/issues/2025 is also resolved.

Environment:

- Python version: 3.11.1
- Jinja version: 3.1.4
