[BUG] number of groups stored as a float; causes reshape scatter matrices to fail
## Summary of issue
The `addData` routine stores the number of energy groups as a float. This causes numpy to fail during the reshaping of scattering matrices.
## Code for reproducing the issue
```
import serpentTools
from serpentTools.settings import rc
rc['xs.reshapeScatter'] = True
r = serpentTools.read('bwr_res.m')
```
## Actual outcome including console output and error traceback if applicable
```
~/.local/lib/python3.5/site-packages/serpentTools-0.4.0+9.g277cb89-py3.5.egg/serpentTools/objects/containers.py in addData(self, variableName, variableValue, uncertainty)
    200                             'should be boolean.'.format(type(uncertainty)))
    201
--> 202         value = self._cleanData(variableName, variableValue)
    203         if variableName in HOMOG_VAR_TO_ATTR:
    204             value = value if variableValue.size > 1 else value[0]

~/.local/lib/python3.5/site-packages/serpentTools-0.4.0+9.g277cb89-py3.5.egg/serpentTools/objects/containers.py in _cleanData(self, name, value)
    233                         .format(name))
    234             else:
--> 235                 value = value.reshape(ng, ng)
    236         return value
    237

TypeError: 'numpy.float64' object cannot be interpreted as an integer
```
## Expected outcome
No error and scattering matrices are reshaped properly

## Versions

* Version  from ``serpentTools.__version__`` `0.4.0+9.g277cb89`

* Python version - ``python --version`` `3.5`

* IPython or Jupyter version if applicable - `ipython 6.2.1`

### Additional contract requirements

- `HomogUniv` objects expose writable `numGroups` and `numMicroGroups` attributes. Assigning a whole-number-valued numeric value, including a `float` or a `numpy.float64`, to either attribute makes it read back as an `int` equal to the assigned number. Numeric values with a fractional part are converted to an integer by discarding that part toward zero.
- Assigning a value that cannot be interpreted as a number raises `TypeError`.
