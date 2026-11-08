Find IR delay - Polyfit Error
I was using the function `pyfar.dsp.find_impulse_response_delay()` and stumbled upon an error that I cannot seem to pinpoint exactly. The function works fine for impulse responses that are very similar to the one I attached to this issue, but for this one, the polynomial fit fails. Maybe you can understand why exactly this IR seems to raise an issue.

Minimal code example
------
```python
import pyfar as pf
import os

s = pf.io.read_audio(os.path.join(os.path.dirname(__file__), "ir_problem.flac"))
pf.dsp.find_impulse_response_delay(s)
```

Error message
---------
File "check_ir.py", line 5, in <module>
    pf.dsp.find_impulse_response_delay(s)
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^
  File "/opt/miniconda3/envs/playground/lib/python3.13/site-packages/pyfar/dsp/dsp.py", line 1325, in find_impulse_response_delay
    search_region_poly = np.polyfit(
        search_region_range[mask]-argmax, search_region[mask], N)
  File "/opt/miniconda3/envs/playground/lib/python3.13/site-packages/numpy/lib/_polynomial_impl.py", line 636, in polyfit
    raise TypeError("expected non-empty vector for x")
TypeError: expected non-empty vector for x

Environment
--------
Python: 3.13.1
pyfar: 0.7.1
Macbook Pro M1

[ir_problem.flac.zip](https://github.com/user-attachments/files/18966566/ir_problem.flac.zip)

### Additional contract requirements

- `pyfar.dsp.find_impulse_response_delay()` must estimate the delay of an impulse response with a dominant negative peak rather than failing during polynomial fitting.
