`BarrierBeforeFinalMeasurements` fails if there are loose qubits or clbits
### Environment

- **Qiskit Terra version**: 0.22
- **Python version**: 3.10
- **Operating system**: macOS


### What is happening?

The `BarrierBeforeFinalMeasurements` pass fails if any of the proceeding operations involve loose qubits or clbits (i.e. those not in registers).

### How can we reproduce the issue?

Loose qubit:
```python
from qiskit.circuit import QuantumCircuit, Qubit, Clbit
from qiskit.transpiler.passes import BarrierBeforeFinalMeasurements

qc = QuantumCircuit([Qubit(), Clbit()])
qc.h(0)
qc.measure(0, 0)
qc.x(0).c_if(0, False)
qc.measure(0, 0)

BarrierBeforeFinalMeasurements()(qc)
```
gives
```text
---------------------------------------------------------------------------
DAGCircuitError                           Traceback (most recent call last)
<ipython-input-2-bca4f6f26fdc> in <module>
      8 qc.measure(0, 0)
      9
---> 10 BarrierBeforeFinalMeasurements()(qc)

~/code/qiskit/terra/qiskit/transpiler/basepasses.py in __call__(self, circuit, property_set)
    119             self.property_set = property_set_
    120
--> 121         result = self.run(circuit_to_dag(circuit))
    122
    123         result_circuit = circuit

~/code/qiskit/terra/qiskit/transpiler/passes/utils/barrier_before_final_measurements.py in run(self, dag)
     62         final_qubits = dag.qubits
     63
---> 64         barrier_layer.apply_operation_back(Barrier(len(final_qubits)), list(final_qubits), [])
     65
     66         # Preserve order of final ops collected earlier from the original DAG.

~/code/qiskit/terra/qiskit/dagcircuit/dagcircuit.py in apply_operation_back(self, op, qargs, cargs)
    619
    620         self._check_condition(op.name, getattr(op, "condition", None))
--> 621         self._check_bits(qargs, self.output_map)
    622         self._check_bits(all_cbits, self.output_map)
    623

~/code/qiskit/terra/qiskit/dagcircuit/dagcircuit.py in _check_bits(self, args, amap)
    504         for wire in args:
    505             if wire not in amap:
--> 506                 raise DAGCircuitError(f"(qu)bit {wire} not found in {amap}")
    507
    508     @staticmethod

DAGCircuitError: '(qu)bit <qiskit.circuit.quantumregister.Qubit object at 0x107e04840> not found in OrderedDict()'
```

Similarly, if I put the qubit in a register and use only the loose clbit, such as by constructing the circuit with
```python
from qiskit.circuit import QuantumCircuit, Qubit, Clbit, QuantumRegister
from qiskit.transpiler.passes import BarrierBeforeFinalMeasurements

qc = QuantumCircuit(QuantumRegister(1), [Clbit()])
qc.h(0)
qc.measure(0, 0)
qc.x(0).c_if(0, False)
qc.measure(0, 0)

BarrierBeforeFinalMeasurements()(qc)
```
I get a similar error on the clbit:
```text
---------------------------------------------------------------------------
DAGCircuitError                           Traceback (most recent call last)
<ipython-input-4-61050a9d8f53> in <module>
      8 qc.measure(0, 0)
      9
---> 10 BarrierBeforeFinalMeasurements()(qc)

~/code/qiskit/terra/qiskit/transpiler/basepasses.py in __call__(self, circuit, property_set)
    119             self.property_set = property_set_
    120
--> 121         result = self.run(circuit_to_dag(circuit))
    122
    123         result_circuit = circuit

~/code/qiskit/terra/qiskit/transpiler/passes/utils/barrier_before_final_measurements.py in run(self, dag)
     71         # Move final ops to the new layer and append the new layer to the DAG.
     72         for final_node in ordered_final_nodes:
---> 73             barrier_layer.apply_operation_back(final_node.op, final_node.qargs, final_node.cargs)
     74
     75         for final_op in final_ops:

~/code/qiskit/terra/qiskit/dagcircuit/dagcircuit.py in apply_operation_back(self, op, qargs, cargs)
    620         self._check_condition(op.name, getattr(op, "condition", None))
    621         self._check_bits(qargs, self.output_map)
--> 622         self._check_bits(all_cbits, self.output_map)
    623
    624         node_index = self._add_op_node(op, qargs, cargs)

~/code/qiskit/terra/qiskit/dagcircuit/dagcircuit.py in _check_bits(self, args, amap)
    504         for wire in args:
    505             if wire not in amap:
--> 506                 raise DAGCircuitError(f"(qu)bit {wire} not found in {amap}")
    507
    508     @staticmethod

DAGCircuitError: "(qu)bit <qiskit.circuit.classicalregister.Clbit object at 0x1150450c0> not found in OrderedDict([(Qubit(QuantumRegister(1, 'q1'), 0), DAGOutNode(wire=Qubit(QuantumRegister(1, 'q1'), 0)))])"
```

### What should happen?

The clbit error is the only one that particularly matters, since `BarrierBeforeFinalMeasurements` is run as part of routing where the qubit registers have already been canonicalised.  We shouldn't be getting an error in the internal structures.

### Any suggestions?

The pass creates a new internal DAG for the barrier layer like this: https://github.com/Qiskit/qiskit-terra/blob/fca8db6b86cba106ed0449a99cd10223899b6145/qiskit/transpiler/passes/utils/barrier_before_final_measurements.py#L53-L58

[HIDDEN]
