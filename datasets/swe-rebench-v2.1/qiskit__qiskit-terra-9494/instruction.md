`Register.name_format` inaccessible as class property during deprecation
### Environment

- **Qiskit Terra version**: 0.23.0
- **Python version**: 3.10
- **Operating system**: macOS


### What is happening?

There used to be some class data `Register.name_format`, which is a regex for testing for valid OQ2 identifiers (ignoring keywords).  It's now deprecated as the naming restrictions on registers were relaxed in #9100, but the deprecation is done wrong - it's no longer usable as a class attribute, only an instance one.

### How can we reproduce the issue?

```python
from qiskit import ClassicalRegister

ClassicalRegister.name_format.match("valid_name")
```

gives

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-5-8200813a2299> in <module>
      1 from qiskit import ClassicalRegister
      2
----> 3 ClassicalRegister.name_format.match("valid_name")

AttributeError: 'property' object has no attribute 'match'
```

### What should happen?

In older Terras, `Register.name_format` was a `re.Pattern` accessible from the class.  It's not much use to need an _instance_ of `Register` to get the valid name formats to pass to its constructor.

### Any suggestions?

_No response_
