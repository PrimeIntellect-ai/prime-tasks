Incorrect `BQM.relabel_variables()` when mapping is a superset of BQM variables
With latest dimod (0.12.20):
```python
>>> import dimod
>>> bqm = dimod.BinaryQuadraticModel({2: 1, 0: 1}, {}, 0, 'SPIN')
>>> bqm.relabel_variables({0: "a", 1: "b", 2: "c"}, inplace=False)
BinaryQuadraticModel({'c': 1.0, 'b': 1.0}, {}, 0.0, 'SPIN')
```
Expected output:
```python
BinaryQuadraticModel({'c': 1.0, 'a': 1.0}, {}, 0.0, 'SPIN')
```
When the order of variables in BQM is reversed, the output is correct.
Also, when the `mapping` dict contains only BQM variables (`{0: "a", 2: "c"}`), the output is correct.
