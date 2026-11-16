[Bug]:  pybam.Experiment parse units error
### PyBaMM Version

24.9.0

### Python Version

python 3.10

### Describe the bug

in https://github.com/pybamm-team/PyBaMM/blob/develop/src/pybamm/experiment/step/base_step.py function def _convert_electric(value_string), if the value_string float value contains 'e' or 'E', the units incorrect parsed:

Python 3.12.3 (main, Nov  6 2024, 18:32:19) [GCC 13.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> value_string = "-1.1729285959021311e-05 W"
>>> unit = value_string.lstrip("0123456789.- ")
>>> unit
'e-05 W'
>>> [HIDDEN]
>>> unit
'W'
>>>

for python3, according to https://docs.python.org/3/library/functions.html#float, should accept 'e' or 'E' as well


### Steps to Reproduce

1.  value_string = "-1.1729285959021311e-05 W"
2.  unit = value_string.lstrip("0123456789.- ")

get incorrect unit 'e-05 W', it should be 'W'

### Relevant log output

```shell

```

### Additional contract requirements

- Add a public function `get_unit_from(a_string: str) -> str` in module `pybamm.experiment.step.base_step`. It returns the unit part of a value string, for example `get_unit_from("123e-1 W")` is `"W"` and `get_unit_from("1e0hours")` is `"hours"`.
- Parsing an electric operating condition whose numeric value uses an `e` or `E` exponent must work through the public step-parsing entry point `pybamm.step.string`. For example, `pybamm.step.string("Discharge at 1.1729285959021311e-05 W for 1 hour")` must produce a step whose value is `1.1729285959021311e-05`.
