numpy DeprecationWarning when quantities with different units are compared.
* unyt version:
2.3.1
* Python version:
3.7
* Operating System:
GNU/Linux & conda env

### Description

We noticed that unyt outputs a deprecationwarning when quantities with different units are compared.
### What I Did

```
In [3]: 1*u.mm == 1*u.V
/opt/miniconda/envs/py3/bin/ipython:1: DeprecationWarning: elementwise comparison failed; this will raise an error in the future.
  #!/opt/miniconda/envs/py3/bin/python
```
Note that no DeprecationWarning is output when the units are rescalable:
```

In [5]: 1*u.mm == 1*u.m
Out[5]: array(False)
```

### Additional contract requirements

- Comparing two quantities whose units have different dimensions with `==` or `!=`
  (equivalently `numpy.equal` or `numpy.not_equal`) must return an element-wise boolean
  result instead of raising: a boolean `numpy.ndarray` for array operands, and a plain
  Python `bool` for 0-D/scalar operands.
- Such comparisons must not emit a `DeprecationWarning`.
- Comparing two quantities whose units have different dimensions with any other
  comparison operator (for example `>` or `numpy.greater`) must raise
  `unyt.exceptions.UnitOperationError`.
