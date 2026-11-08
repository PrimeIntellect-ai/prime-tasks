print_readable_snapshot() of instrument modules without parameters broken.
### `print_readable_snapshot()` of instrument modules without parameters fails.

### Steps to reproduce
```python
from qcodes import instrument
bar = instrument.Instrument('bar')
foo = instrument.InstrumentModule(bar, 'foo')
bar.add_submodule('foo', foo)
```
Calling `print_readable_snapshot()` on either the submodule or the parent instrument fails:
```python
>>> bar.print_readable_snapshot()
  File ~\Documents\Qcodes\src\qcodes\instrument\instrument_base.py:406 in print_readable_snapshot
    par_field_len = min(max(par_lengths) + 1, 50)

ValueError: max() arg is an empty sequence
```
[HIDDEN]

Branch: main @ https://github.com/QCoDeS/Qcodes/commit/42c74833d227a85ee45d7812e1ac0f66b8d948b0

### Additional contract requirements

- Calling `print_readable_snapshot()` on an instrument module with no parameters, or on its parent instrument, must complete without raising an exception.
