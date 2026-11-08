`PauliList.evolve` raises exception when evolving certain Clifford circuits.
### Environment

- **Qiskit Terra version**:  0.21.1
- **Python version**: 3.9
- **Operating system**: MacOS 11.6.7


### What is happening?

There is a bug in the `BasePauli/PauliList/Pauli` classes where the phase vector is sometimes set as dtype `uint8` instead of `int64` leading to errors when calling the `evolve` function for circuits containing gates that modify the pauli phase vector.

Whether this happens or not seems to depend on how the Pauli is initialized (sometimes it will be initialized with uint8 phase vector, other times with int64 phase vector).

### How can we reproduce the issue?

Minimal example

```python
from qiskit import QuantumCircuit
import qiskit.quantum_info as qi

# Create circuit with gate that modifies Pauli phase
qc = QuantumCircuit(2)
qc.cz(0, 1)

# Generate random Pauli
pauli = qi.random_pauli(2, seed=123)

# Try and evolve
pauli.evolve(qc)
```

Give the exception:
```
---------------------------------------------------------------------------
UFuncTypeError                            Traceback (most recent call last)
/var/folders/lp/ftt3j6qs7s90j6h9wszq3jcw0000gn/T/ipykernel_71613/3628800509.py in <module>
      7 pauli = qi.random_pauli(2, seed=123)
      8 #qc = qi.random_clifford(4, seed=123).to_circuit()
----> 9 pauli.evolve(qc)

~/anaconda3/envs/qiskit/lib/python3.9/site-packages/qiskit/quantum_info/operators/symplectic/pauli.py in evolve(self, other, qargs, frame)
    597             other = Pauli(other)
    598
--> 599         return Pauli(super().evolve(other, qargs=qargs, frame=frame))
    600
    601     # ---------------------------------------------------------------------

~/anaconda3/envs/qiskit/lib/python3.9/site-packages/qiskit/quantum_info/operators/symplectic/base_pauli.py in evolve(self, other, qargs, frame)
    277         if frame == "s":
    278             return self.copy()._append_circuit(other, qargs=qargs)
--> 279         return self.copy()._append_circuit(other.inverse(), qargs=qargs)
    280
    281     def _evolve_clifford(self, other, qargs=None, frame="h"):

~/anaconda3/envs/qiskit/lib/python3.9/site-packages/qiskit/quantum_info/operators/symplectic/base_pauli.py in _append_circuit(self, circuit, qargs)
    585             # Get the integer position of the flat register
    586             new_qubits = [qargs[bit_indices[tup]] for tup in instruction.qubits]
--> 587             self._append_circuit(instruction.operation, new_qubits)
    588
    589         # Since the individual gate evolution functions don't take mod

~/anaconda3/envs/qiskit/lib/python3.9/site-packages/qiskit/quantum_info/operators/symplectic/base_pauli.py in _append_circuit(self, circuit, qargs)
    558             if len(qargs) != 2:
    559                 raise QiskitError("Invalid qubits for 2-qubit gate.")
--> 560             return basis_2q[name](self, qargs[0], qargs[1])
    561
    562         # If not a Clifford basis gate we try to unroll the gate and

~/anaconda3/envs/qiskit/lib/python3.9/site-packages/qiskit/quantum_info/operators/symplectic/base_pauli.py in _evolve_cz(base_pauli, q1, q2)
    661     base_pauli._z[:, q1] ^= x2
    662     base_pauli._z[:, q2] ^= x1
--> 663     base_pauli._phase += 2 * np.logical_and(x1, x2).T
    664     return base_pauli
    665

UFuncTypeError: Cannot cast ufunc 'add' output from dtype('int64') to dtype('uint8') with casting rule 'same_kind'
```

### What should happen?

The dtype of the phase vector should always be the same, so that evolution and other methods that attempt to inplace modify the vector don't cause exceptions for mismatched dtypes.

### Any suggestions?

One fix would be to explicitly cast the phase vector when initializing base pauli

### Additional contract requirements

- When evolving a Pauli with a phase array of dtype `int`, `np.int8`, `np.uint8`, `np.int16`, `np.uint16`, `np.int32`, `np.uint32`, `np.int64`, or `np.uint64` through an `IGate`, `XGate`, `YGate`, `ZGate`, `HGate`, `SGate`, `SdgGate`, `CXGate`, `CYGate`, `CZGate`, or `SwapGate`, the resulting `evo.phase.dtype` must equal the input phase dtype.
- The same dtype-preservation requirement applies to `PauliList.evolve`: when a `PauliList` is constructed with a phase array of one of the listed dtypes and evolved through any of the listed gates, the resulting `evo.phase.dtype` must equal the input phase dtype.
