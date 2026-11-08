Use of constant parameter functions throws an error
If one uses any model (inbuilt or self-made) with a function parameter that doesn't process any of the variables, its output won't be a Symbol, but a float.

Steps ro reproduce the error most easily:
1. Load up the example notebook/script for e.g. the DFN model.
2. Add/Update the following parameter in the default parameter set:
    "Electrolyte diffusivity [m2.s-1]": lambda c_e, T, T_ref, E_D_e, R: 2.72e-10,
3. Run the notebook/script.
4. See beautiful error message at the end. It basically fails at the step where 2.72e-10 obviously has no ".id" field, since it's not a Symbol.

While this is easily fixed by multiplying the 2.72e-10 by (0 * T_ref + 1) or replacing it with pybamm.Scalar(2.72e-10), I think this might be a common issue for beginners when using a model with more complexity than needed. Thus I'd like a helpful error message that hints me at my error. Or even better: constant parameter functions get converted to an appropriate Symbol automatically, just like it happens with scalar parameters already.

I monkey-patched the following hint-giver in my local copy (0.2.0 pip install) for my purposes:
[HIDDEN]
This displays "A parameter was not given as a 'Symbol': 2.72e-10" in the example case. I didn't figure out how to get the parameter name in this context.



Beautiful error message:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: -1310443411252241803

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: 6247489124244137513

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: -5616125575659663777

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: -9191736092148201685

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: -8136991043322325845

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
KeyError: -5859718582323950464

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "solve.py", line 86, in <module>
    parameters.process_model(model)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 350, in process_model
    model.rhs[variable] = self.process_symbol(equation)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 531, in _process_symbol
    new_child = self.process_symbol(symbol.child)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 531, in _process_symbol
    new_child = self.process_symbol(symbol.child)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 522, in _process_symbol
    new_left = self.process_symbol(symbol.left)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 522, in _process_symbol
    new_left = self.process_symbol(symbol.left)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 523, in _process_symbol
    new_right = self.process_symbol(symbol.right)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 469, in process_symbol
    processed_symbol = self._process_symbol(symbol)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 518, in _process_symbol
    return self.process_symbol(function_out)
  File "/usr/local/lib/python3.7/dist-packages/pybamm/parameters/parameter_values.py", line 467, in process_symbol
    return self._processed_symbols[symbol.id]
AttributeError: 'float' object has no attribute 'id'

### Additional contract requirements

- A function parameter whose function returns a plain number (a constant that does
  not depend on its inputs) must be handled without raising the internal
  `AttributeError` shown above. The implementation must either:
  - convert the constant result to an appropriate `pybamm.Symbol` (for example a
    `pybamm.Scalar` whose value equals the returned number), or
  - raise a helpful error instead. The error may be of any type except
    `AttributeError`; the internal `AttributeError` (`'float' object has no
    attribute 'id'`) produced by the bug is not a helpful error.
