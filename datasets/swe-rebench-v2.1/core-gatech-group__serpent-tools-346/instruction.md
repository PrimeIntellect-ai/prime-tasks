BUG Burnup and day values wrong for results with multiple gcu, no burnup
## Summary of issue
When reading a result file with multiple homogenized universes and no burnup, the homogenized universes have incorrect values of burnup and days.

## Code for reproducing the issue
Reading a file with four homogenized universes, (50, 60, 70, 80) and no burnup
```
>>> r = serpentTools.read("core_res.m")
>>> r.universes.keys()
dict_keys([
    UnivTuple(universe='50', burnup=0, step=0, days=0),
    UnivTuple(universe='60', burnup=1, step=0, days=1),
    UnivTuple(universe='70', burnup=2, step=0, days=2),
    UnivTuple(universe='80', burnup=3, step=0, days=3)])
```
## Expected outcome
All values of `burnup` and `days` should be zero. The bug exists on the develop branch and master branch [0.7.1] but the keys are plain tuples.

## Versions

* Version  from ``serpentTools.__version__`` `0.7.1-48-g09a5fea` and `0.7.1`
* Python version - ``python --version`` 3.7.4
