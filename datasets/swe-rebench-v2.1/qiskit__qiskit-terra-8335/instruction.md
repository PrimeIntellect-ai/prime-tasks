Improve TwoLocal and RealAmplitudes synthesis when entanglement='full'
### What should we add?

When choosing a `TwoLocal` or `RealAmplitude` or `EfficientSU2` gate with `entanglement=full` on n-qubits (for VQE ansatz),
then we get a circuit with a CX sub-circuit that contains `n*(n-1)/2` CX gates.
However, we can re-write this circuit with only `n-1` CX gates with a linear connectivity (see a code example below).

```
from qiskit.circuit.library import *
from qiskit.quantum_info import Operator

n = 5
# print (RealAmplitudes(n, reps=1, insert_barriers=True).decompose())
# now note that the CX-subcircuit is in fact the same as this qc below

qc = QuantumCircuit(n)
for i in range(n):
    for j in range(i+1, n):
        qc.cx(i,j)
# print ("qc", qc)
mat = LinearFunction(qc).linear
op = Operator(qc)

qc1 = QuantumCircuit(n)
[HIDDEN]
# print ("qc1", qc1)
mat1 = LinearFunction(qc).linear
op1 = Operator(qc1)

print((mat == mat1).all())
print (op == op1)
```

outputs:
```
True
True
```

It will be good to update either `NLocal` or `TwoLocal` to consider this specific enhancement,
as it seems that this is used in many applications.

### Additional contract requirements

`TwoLocal`-family ansatz circuits must accept `entanglement="reverse_linear"`. For CX entanglement blocks, this pattern uses exactly n−1 CX gates per layer between adjacent qubits and implements the same operation as full entanglement.
