Estimator fails when reused
### Environment

- **Qiskit Terra version**: 0.22
- **Python version**: 3.9
- **Operating system**:  Linux


### What is happening?

Estimated value can be incorrect when using an Estimator for different observables.

### How can we reproduce the issue?

Run this code. Uncomment the Estimator in the loop to see the alternating values it should produce

```
from qiskit.opflow.primitive_ops import PauliSumOp
from qiskit.primitives import Estimator
from qiskit.circuit import QuantumCircuit

qc = QuantumCircuit(4)
qc.ry(3, 0)
qc.rz(1.1, 0)
qc.cx(0, 1)
qc.h(1)
qc.cx(1, 2)
qc.rx(1.2, 2)
qc.rz(2.1, 3)
qc.cx(3, 0)

num_ops = 2
def get_op(num_op):
  if num_op == 0:
    op = PauliSumOp.from_list(
        [
            ("IXIX", 6.727086146309219),
            ("IXZX", -0.727086146309219),
            ("ZXZX", -1.727086146309219),
            ("ZXIX", 1.727086146309219),
        ]
    )
  else:
    op = PauliSumOp.from_list(
        [
            ("ZXIX", 0.727086146309219),
            ("ZXZX", -0.727086146309219),
            ("IXZX", -0.727086146309219),
            ("IXIX", 0.727086146309219),
        ]
  )
  return op

estimator = Estimator()

for j in range(10):
    # estimator = Estimator()
    num_op = j % num_ops
    job = estimator.run([qc], [get_op(num_op)])
    value = job.result().values[0]
    print(value)
```

### What should happen?

It should give the right values

### Any suggestions?

[HIDDEN]

### Additional contract requirements

- Reusing an Estimator for different observables must produce the correct estimated value for each observable.
