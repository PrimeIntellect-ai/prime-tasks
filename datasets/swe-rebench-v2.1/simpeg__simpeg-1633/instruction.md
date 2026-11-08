BUG: Inconsistency between docstring and result of `simpeg.potential_fields.gravity.survey.Survey.components()`
### Describe the issue:

There is an inconsistency between the docstring of the `components` property of `simpeg.potential_fields.gravity.survey.Survey`, and the output of the function. The relevant lines of code are here:

https://github.com/simpeg/simpeg/blob/2e3689625225955cc338dadad13cb3cdb4310e8b/simpeg/potential_fields/gravity/survey.py#L77-L86

The docstring indicates the method returns the number of components at each receiver. However the function returns instead the list of strings representing the components of the first receiver.

There are a few cases where this causes unintended outputs.

### Unintended output 1: Expect an int, get an array of strings

This is the simplest case. We have 2 components defined for the receiver, so the expected output is 2. However, the list of strings representing the components of the first receiver, i.e., `['gx', 'gz']`.

```python
r = gravity.receivers.Point([0, 0, 0], ["gx", "gz"])

source_field = gravity.sources.SourceField(receiver_list=[r])

survey = gravity.survey.Survey(source_field)

# Inspect the components of the survey object
print(survey.components)

# Returns: ['gx', 'gz']
# Expected: 2
```

### Unintended output 2: Different components for different receivers

Here the same number of receivers are defined for each receiver, but different types of component are defined at each receiver. Here the output is the component(s) of the first receiver. What should the expected result be here though? Should it be 1, as each receiver (in the list) has 1 component? Or should it be 2, as there are 2 components in the receiver list?

```python
from simpeg.potential_fields import gravity

rx = gravity.receivers.Point([0, 0, 0], ["gx"])
rz = gravity.receivers.Point([0, 0, 0], ["gz"])

source_field = gravity.sources.SourceField(receiver_list=[rx, rz])

survey = gravity.survey.Survey(source_field)

# Inspect the components of the survey object
print(survey.components)

# Returns: ['gx']
# Expected: 1 or 2
```

### Unintended output 3: Different numbers of components for each point receiver

One can define different numbers of components for different receivers. Here the value returned is the component(s) of the first receiver. But I think here the expected output is not well defined.

```python
r1 = gravity.receivers.Point([0, 0, 0], ["gx"])
r2 = gravity.receivers.Point([0, 0, 0], ["gx", "gz"])

source_field = gravity.sources.SourceField(receiver_list=[r1, r2])

survey = gravity.survey.Survey(source_field)

# Inspect the components of the survey object
print(survey.components)

# Returns: ['gx']
# Expected: ???
```

## Final thoughts

 - A fix for this will make the docstring and implementation consistent. However, it should be clear what the intended use is.
 - This inconsistency may be present in other survey classes. I haven't had a chance to look yet. I'll update here if I find more.

### Reproducible code example:

```python
from simpeg.potential_fields import gravity

r = gravity.receivers.Point([0, 0, 0], ["gx", "gz"])

source_field = gravity.sources.SourceField(receiver_list=[r])

survey = gravity.survey.Survey(source_field)

# Inspect the components of the survey object
print(survey.components)

# Returns: ['gx', 'gz']
# Expected: 2
```

### Error message:

```shell

```

### Runtime information:

--------------------------------------------------------------------------------
  Date: Thu Feb 20 16:57:00 2025 PST

                OS : Darwin (macOS 14.6.1)
            CPU(s) : 12
           Machine : arm64
      Architecture : 64bit
               RAM : 36.0 GiB
       Environment : Python
       File system : apfs

  Python 3.12.2 | packaged by conda-forge | (main, Feb 16 2024, 20:54:21)
  [Clang 16.0.6 ]

            simpeg : 0.23.0
        discretize : 0.11.1
       pymatsolver : 0.3.1
             numpy : 2.2.2
             scipy : 1.15.1
        matplotlib : 3.10.0
            geoana : 0.7.2
            libdlf : 0.3.0
           sklearn : 1.6.1
            pandas : 2.2.3
             sympy : 1.13.1
           IPython : 8.30.0
        ipywidgets : 8.1.5
            plotly : 5.24.1
               vtk : 9.3.1
--------------------------------------------------------------------------------

### Context for the issue:

_No response_

### Additional contract requirements

The resolution for this issue is to deprecate the `components` property in the
potential field surveys rather than change its return value. Accessing
`gravity.survey.Survey.components` or `magnetics.survey.Survey.components` must
emit a `FutureWarning` whose message contains the exact phrase
"The `components` property is deprecated". The deprecated property is retained
for backwards compatibility, so this contract does not require changing its
return value (the "expected output is 2" mentioned above is not part of this
contract).
