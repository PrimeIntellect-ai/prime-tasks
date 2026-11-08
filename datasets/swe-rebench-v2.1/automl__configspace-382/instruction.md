Bug: cannot print a Configuration with a Constant that is a list or a tuple
Example:

```
from ConfigSpace import ConfigurationSpace, Constant, Integer

cs = ConfigurationSpace()
tags = ["a", "b", "c"]
cs.add(Constant('tags', tags))
config = cs.sample_configuration()
print(config)
```

The `print` statement throws this:

```
Traceback (most recent call last):
  File "/home/ubuntu/Code/mochi-bedrock/build/ttt.py", line 10, in <module>
    print(cs.sample_configuration())
  File "/home/ubuntu/Code/spack/var/spack/environments/bedrock-env/.spack-env/view/lib/python3.11/site-packages/ConfigSpace/configuration.py", line 247, in __str__
    values = dict(self)
             ^^^^^^^^^^
  File "/home/ubuntu/Code/spack/var/spack/environments/bedrock-env/.spack-env/view/lib/python3.11/site-packages/ConfigSpace/configuration.py", line 226, in __getitem__
    value = hyperparameter.to_value(vector)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ubuntu/Code/spack/var/spack/environments/bedrock-env/.spack-env/view/lib/python3.11/site-packages/ConfigSpace/hyperparameters/hyperparameter.py", line 357, in to_value
    value: DType = self._transformer.to_value(np.array([vector]))[0]
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
    [HIDDEN]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ubuntu/Code/spack/var/spack/environments/bedrock-env/.spack-env/view/lib/python3.11/site-packages/numpy/core/numeric.py", line 407, in full_like
    multiarray.copyto(res, fill_value, casting='unsafe')
ValueError: could not broadcast input array from shape (3,) into shape (1,)
```

### Additional contract requirements

- A `Configuration` that contains a `Constant` whose value is a list or a tuple must be
  printable: `str(config)` (and therefore `print(config)`) must not raise an exception.
- The value of such a `Constant` is preserved unchanged, i.e. `config[name]` returns the
  same list or tuple that was passed to the `Constant`.
