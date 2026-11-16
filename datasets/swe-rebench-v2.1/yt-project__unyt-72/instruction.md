Creating UnitSystem based on actual "units" doesn't appear to work in 2.0.0
* unyt version: 2.0.0
* Python version: 3.7.2
* Operating System: MacOS

### Description

I have a custom unit system, called `cosmological`, that I use for my thin i/o wrapper for SWIFT. It's defined in the following way:

```
import unyt

cosmo_units = unyt.UnitSystem(
    "cosmological", unyt.Mpc, 1e10 * unyt.msun, unyt.s * unyt.Mpc / unyt.km
)
```
This broke our test suite in `unyt2.0.0`.

### What I Did

Minimal breaking example below:
```
>>> import unyt
>>> unyt.UnitSystem("cosmological", "Mpc", "Msun", "s")
cosmological Unit System
 Base Units:
  length: Mpc
  mass: Msun
  time: s
  temperature: K
  angle: rad
  current_mks: A
  luminous_intensity: cd
 Other Units:
>>> unyt.UnitSystem("cosmologicalRealUnits", unyt.Mpc, unyt.Msun, unyt.s)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/mphf18/Documents/swift/swiftsimio/env/lib/python3.7/site-packages/unyt/unit_systems.py", line 218, in __init__
    bu = _split_prefix(unit, default_lut)[1]
  File "/Users/mphf18/Documents/swift/swiftsimio/env/lib/python3.7/site-packages/unyt/unit_systems.py", line 111, in _split_prefix
    possible_prefix = symbol_str[0]
TypeError: 'Unit' object does not support indexing
```
This seems to work fine if I pass strings, but if I pass real units then it doesn't work. This is a pain as I want to use 1e10 solar masses as my mass unit.

Am I doing something wrong here?
