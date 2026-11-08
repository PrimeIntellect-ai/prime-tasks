The upper/lower bounds cannot be successfully imposed on a model app
**Describe the bug**
No response when setting parameters for upper and lower bounds during the initialization of a model app. The docstring indicates "bounds for all rate and length parameters"; it should control the global settings for rate and length.

**To Reproduce**

```
>>> from cogent3 import make_aligned_seqs, get_app

>>> algn = make_aligned_seqs({"a":"ACTG", "b":"TGGC", "c":"GGCA"}, moltype="DNA")
>>> modeller = get_app("model", "GTR", upper = 99, lower=9)
>>> res = modeller(algn)
>>> res.lf.get_param_rules()

[... {'par_name': 'C/T',
  'init': np.float64(0.9929720035793337),
  'lower': 1e-06,
  'upper': 1000000.0},
   ...
   {'par_name': 'length',
  'edge': 'b',
  'init': np.float64(9.999981165175347),
  'lower': 0.0,
  'upper': 10.0}... ]
```

**Expected output**

```
[... {'par_name': 'C/T',
  'init': np.float64(0.9929720035793337),
  'lower': 9,
  'upper': 99},
   ...
   {'par_name': 'length',
  'edge': 'b',
  'init': np.float64(9.999981165175347),
  'lower': 9,
  'upper': 99}... ]
```
