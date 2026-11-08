DoubleSliceSpan.mask crashes
**Describe the bug**

It crashes in a real-world case, coming from a real execution result.


**Steps to reproduce**

```python
from qiskit_ibm_runtime.execution_span.double_slice_span import DoubleSliceSpan

span = DoubleSliceSpan(1, 2, {0: ((7,), slice(0, 1, None), slice(0, 7, None))})
span.mask(0)
```

Output:
```
Traceback (most recent call last):
  File "/mnt/wsl/balagan/doubleslicespan_mask_bug.py", line 4, in <module>
    span.mask(0)
  File "/root/miniforge3/envs/env5/lib/python3.11/site-packages/qiskit_ibm_runtime/execution_span/double_slice_span.py", line 73, in mask
    mask.reshape([HIDDEN], shape[-1])[(args_sl, shots_sl)] = True
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: 'numpy.float64' object cannot be interpreted as an integer
```


**Expected behavior**


**Suggested solutions**


**Additional Information**

- **qiskit-ibm-runtime version**: 0.34.0
- **Python version**: 3.11.10
- **Operating system**: Linux (Windows + WSL)

### Additional contract requirements

- Calling `DoubleSliceSpan.mask(0)` for the one-dimensional shape shown in the reproduction must complete without raising.
