Instantiating a qt.QobjEvo with a qt.coefficient
It is possible to instantiate a qt.QobjEvo object with a qt.coefficient. However, the "args" argument QobjEvo does not behave as expected. Is this a bug, or is it incorrect to pass a qt.coefficient object to qt.QobjEvo? I am using qutip v5.0.4

```
import qutip as qt
A = qt.sigmaz()
def f(t, args):
    return t + args["g"]

coeff = qt.coefficient(f, args={"g":1})

evo_1 = qt.QobjEvo([A, coeff])
evo_2 = qt.QobjEvo([A, coeff], args={"g:2}) # Updating the args dictionary does nothing.

assert evo_1(1) == evo_2(1)
```

### Additional contract requirements

A `qt.coefficient` may be used as the time-dependent coefficient in a `[Qobj, coefficient]` term of a `QobjEvo`. When `args` are supplied to `QobjEvo`, their values must be used to evaluate that coefficient and must override existing coefficient argument values for matching keys.
