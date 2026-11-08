`SabreSwap` can reorder operations that depend on the same classical bit
### Environment

- **Qiskit Terra version**: main @ ef997f9
- **Python version**: any
- **Operating system**: any

### What is happening?

`SabreSwap` can re-order measurement operations (and probably classically conditioned gates) that write to the same classical bits.  This affects optimisation level 3 by default, since it uses sabre to route if nothing else is provided.

I am 95% sure this is the cause of the failures we're seeing in the randomised test suite currently.

<details><summary>Expand for logs of recent failed randomised run</summary>
Hypothesis failure at commit 618e0ea8b3daca194c1bde97292e57c15eddd762, in file `test/randomized/test_transpile_equivalence.py`

```text
Falsifying example:
state = QCircuitMachine()
state.qasm()
(v1,) = state.add_creg(n=1)
state.qasm()
v2, v3, v4 = state.add_qreg(n=3)
state.qasm()
state.add_3q_gate(gate=qiskit.circuit.library.standard_gates.x.CCXGate, qargs=[v4, v3, v2])
state.qasm()
state.add_1q1c_gate(carg=v1, gate=qiskit.circuit.measure.Measure, qarg=v3)
state.qasm()
state.add_1q2p_gate(gate=qiskit.circuit.library.standard_gates.u2.U2Gate, params=[0.0, 0.0], qarg=v4)
state.qasm()
state.add_1q1c_gate(carg=v1, gate=qiskit.circuit.measure.Measure, qarg=v4)
state.qasm()
Evaluating circuit at level 3 on fake_ourense:
OPENQASM 2.0;
include "qelib1.inc";
qreg q35069[3];
creg c1656[1];
ccx q35069[2],q35069[1],q35069[0];
measure q35069[1] -> c1656[0];
u2(0,0) q35069[2];
measure q35069[2] -> c1656[0];

state.equivalent_transpile(backend=<FakeOurense('fake_ourense')>, opt_level=3)
state.teardown()

You can reproduce this example by temporarily adding @reproduce_failure('6.43.2', b'AXicY2Bk5GFgYGDkZWBiYARCIBPIYmAE8thAbEYOBkwAkgKSrEBlzAALaABL') as a decorator on your test case
```
</details>

### How can we reproduce the issue?

Given a circuit:
```python
import qiskit

qc = qiskit.QuantumCircuit(3, 1)
qc.ccx(2, 1, 0)
qc.h(0)
qc.measure(0, 0)
qc.measure(1, 0)
```
which has a drawing
```text
     ┌───┐┌───┐┌─┐
q_0: ┤ X ├┤ H ├┤M├───
     └─┬─┘└───┘└╥┘┌─┐
q_1: ──■────────╫─┤M├
       │        ║ └╥┘
q_2: ──■────────╫──╫─
                ║  ║
c: 1/═══════════╩══╩═
                0  0
```
Clearly the output of the circuit should always be 0, because qubit 1 is never altered, and is measured second.

If we transpile it with a special coupling map that essentially only has one valid routing for the default decomposition of ccx, the orders of the measurements get flipped, which Aer confirms:
```python
transpiled = qiskit.transpile(qc, coupling_map=[[(0, 2), (2, 0), (1, 2), (2, 1)]], routing_method="sabre")
backend = qiskit.Aer.get_backend("aer_simulator")
print(backend.run(qc, shots=1024).result().get_counts())
print(backend.run(transpiled, shots=1024).result().get_counts())
```
This produces, for example:
```python
{'0': 1024}
{'1': 503, '0': 521}
```
but the second dictionary should be the same as the first.

(It's too long to draw `transpiled` here, but if you do it locally, you can see the measurements are swapped.)

### What should happen?

Sabre should take into account the topological ordering of measurements (and other clbits).  In the above examples, the counts should both be `{'0': 1024}` (which they are for any other routing method).

### Any suggestions?

[HIDDEN]

### Additional contract requirements

SabreSwap must preserve the topological order of operations that depend on classical bits, including measurements that write to the same classical bit and other operations with classical-bit operands. Routing may change physical wires or add routing operations, but must not change the resulting circuit behavior.
