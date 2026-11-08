Bound `ParameterExpression`s do not match the hash of an equal object of a numeric type
### Environment

- **Qiskit version**: 1.1.0
- **Python version**: 3.11
- **Operating system**: Fedora Linux 40


### What is happening?

When all the parameters in a `ParameterExpression` are bound, it becomes equal to a `float`, `int`, or `complex`. However, it still uses its own hashing algorithm, so it does not hash to the same value as the numeric type. The Python data model documents that objects that compare equal should hash to the same value.

### How can we reproduce the issue?

```
from qiskit.circuit import Parameter


a = Parameter("a")
b = a.bind({a: 1.2})
b == 1.2  # True
hash(b)  == hash(1.2)  # False
```

### What should happen?

As much as possible, the Python data model should be followed. At some points in the parameter handling code, bound `ParameterExpression`s are eagerly cast to `float`. For example, the `float(p)` here:

https://github.com/Qiskit/qiskit/blob/26886a1b2926a474ea06aa3f9ce9e11e6ce28020/qiskit/transpiler/passes/scheduling/scheduling/base_scheduler.py#L71

I think this is done to avoid a bound `p` failing the lookup if the calibrations dict was keyed with a plain `float`. It would be preferable not to have to deal with type casting in these cases.

### Any suggestions?

_No response_
