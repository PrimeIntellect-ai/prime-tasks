Params indexed by infinite sets with default value cannot be pretty-printed
<!-- DO NOT DELETE OR IGNORE THIS TEMPLATE.  Failing to adhere to this template and provide the necessary information may lead to your Issue being closed without consideration. -->

## Summary
Pyomo parameters indexed by infinite sets and *with* a default value cannot be `pprint`-ed

<!-- Explain, in a clear and concise way, the command you ran and the result you were trying to achieve.
Example: "I ran `pyomo solve` to optimize a model and ..." -->

### Steps to reproduce the issue

<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->

```python
import pyomo.environ as pyo

m = pyo.ConcreteModel()
m.p = pyo.Param(pyo.Any, default=1)

# lazy creation works fine
assert m.p["foo"] == 1

# pprint does not...
m.p.pprint()
```

### Error Message

<!-- If Pyomo reported an error, provide the error message. PLEASE INCLUDE THE ENTIRE STACK TRACE. -->

<!-- If it did not report an error but the output appears incorrect, provide the incorrect output. If there was no error message and no output but the result is incorrect, describe how it does not match what you expect. -->
```console
Traceback (most recent call last):
  File "/Users/bknueven/Software/mpi-sppy/pyo_param_bug.py", line 9, in <module>
    m.p.pprint()
  File "/Users/bknueven/anaconda3/envs/mpisppy/lib/python3.11/site-packages/pyomo/core/base/component.py", line 580, in pprint
    *self._pprint()
     ^^^^^^^^^^^^^^
  [HIDDEN]
TypeError: object of type 'Any' has no len()
```

### Information on your system

Pyomo version: 6.8.0
Python version: 3.11.9
Operating system: macOS
How Pyomo was installed (PyPI, conda, source): PyPI
Solver (if applicable): N/A

### Additional contract requirements

- Calling `pprint()` on a `Param` indexed by an infinite set with a default value must complete without raising, including after a key is accessed and its default value is returned.
