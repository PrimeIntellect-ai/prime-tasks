String conversion of Expression not correct
<!-- DO NOT DELETE OR IGNORE THIS TEMPLATE.  Failing to adhere to this template and provide the necessary information may lead to your Issue being closed without consideration. -->

## Summary

<!-- Explain, in a clear and concise way, the command you ran and the result you were trying to achieve.
Example: "I ran `pyomo solve` to optimize a model and ..." -->
I was looking at the string representation of an expression, when I noticed that the representation does not handle squared negative numbers correctly.

### Steps to reproduce the issue

<!-- Please include the command run and/or provide an example script that demonstrates the problem. -->

```
import pyomo.environ as pyo

model = pyo.ConcreteModel()

model.A = pyo.Expression(initialize=1)
model.B = pyo.Expression(initialize=-2)

print(model.A**2 + model.B**2)
```

### Error Message

<!-- If Pyomo reported an error, provide the error message. PLEASE INCLUDE THE ENTIRE STACK TRACE. -->

<!-- If it did not report an error but the output appears incorrect, provide the incorrect output. If there was no error message and no output but the result is incorrect, describe how it does not match what you expect. -->
No errors were reported, but this was the output:
```console
1**2 - 2**2
```

### Information on your system

Pyomo version: 6.8.2
Python version: 3.10.16
Operating system: Windows 10
How Pyomo was installed (PyPI, conda, source): PyPI
Solver (if applicable): N/A


### Additional information

<!-- If you have any additional information, please list it here. -->

The output I would have expected:
```console
1**2 + (-2)**2
```

<!-- We encourage you to try, as much as possible, to reduce your problem to the minimal example that still reproduces the issue. That would help us a lot in fixing it quickly and effectively!

If you want to ask a question (how to use Pyomo, what it can do, etc.), please refer to our [online documentation](https://github.com/Pyomo/pyomo#getting-help) on ways to get help. -->
