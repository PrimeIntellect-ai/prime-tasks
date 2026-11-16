Define `__iter__` and/or `__contains__` for `pybamm.ParameterValues`
### Description

The `pybamm.ParameterValues` is dict-like, and through its `__getitem__` and `__setitem__` methods allows dict-like key access. However, it does not support the `in` keyword, which for a dict will treat the keys as an iterable. This means that natural code like:

```python
if "Negative particle radius [m]" in parameter_values:
    # do something
```

will not work (generally raises a `KeyError`). It is currently necessary to instead write explicitly:

```python
if "Negative particle radius [m]" in parameter_values.keys():
    # do something
```

Defining the missing method `__iter__` (and `__contains__` if preferred) would allow `in` to work in logical test and for-loop contexts.

### Motivation

Code is cleaner if `pybamm.ParameterValues` looks like a souped-up dict always, not just sometimes. Key-value accessors are expected to iterate over their keys and to allow logical test on the presence/absence of keys. PyBaMM-containing code looks 'asymmetric' compared to code working with actual `dict` objects due to the requirement to call into `pybamm.ParameterValues.keys()` specifically.

Was there any historic reason for the decision to exclude these methods?

### Possible Implementation

_No response_

### Additional context

_No response_
