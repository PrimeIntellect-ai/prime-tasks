Remove symbolic pulse subclasses
### What should we add?

### Background

We have four parametric pulse subclass in pulse library, namely, `Gaussian`, `GaussianSquare`, `Drag`, `Constant`.
```python
from qiskit.pulse.library import Gaussian
instance = Gaussian(160, 0.1, 40)
```
This returns a class instance dedicated to each waveform kind.

In #7821 , we replaced the base class of them from `ParametricPulse` to `SymbolicPulse`. In contrast to parametric pulse, symbolic pulse can uniquely determine waveform with instance variables `self._envelope` and `self._pulse_type` which are a symbolic equation and string, respectively. This means, these subclasses are no longer necessary and we can turn everything into symbolic pulse instance. This can simplify the deserialization logic of QPY (actually type information is not stored).

### Proposal

I want to convert `Gaussian` class into a symbolic pulse factory while keeping camel case :
```python
def Gaussian(duration, amp, sigma, name, limit_amplitude):
    ...
    return SymbolicPulse(...)
```
so that user code works without deprecation, e.g.
```python
with build() as schedule:
    # now the first arg is SymbolicPulse, rather than Gaussian
    play(Gaussian(160, 0.1, 40), DriveChannel(0))
```

### Problems
However, sometimes type information is used in the codebase. For example, in the RZX transpiler pass:
https://github.com/Qiskit/qiskit-terra/blob/10822404936e98df01f2975ef43b8378006621ba/qiskit/transpiler/passes/calibration/builders.py#L163-L168
I can update such use case in our codebase. This can be written without type information like below.
```python
if pulse_.pulse_type == "GaussianSquare":
```
However, because we have never prohibited users from using type information, we need proper communication with some warning mechanism. Adding deprecation warning in symbolic pulse constructor is very annoying since it will issue tones of warnings (e.g. loading each pulse in backend CmdDef). Probably overriding `__instancecheck__` method to show deprecation warning is possible, however, this is not sensitive to, for example, `__class__.__name__`.

### Additional contract requirements

- Legacy `isinstance` checks against `Gaussian`, `GaussianSquare`, `Drag`, or `Constant` must continue to report whether the pulse has that waveform kind and emit a deprecation warning. Either `DeprecationWarning` or `PendingDeprecationWarning` is suitable.
- Loading a symbolic pulse from QPY must preserve its waveform kind without recreating a waveform-specific subclass.
