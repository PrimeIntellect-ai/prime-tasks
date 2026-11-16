Phased XX - YY interaction gate
### What should we add?

Gate for phased XX-YY interaction. This gate has the same exact definition as [XYGate](https://github.com/Qiskit/qiskit-terra/blob/517265c26e91baac44a690fafe1f473ad89d70b2/qiskit/circuit/library/standard_gates/xy.py) but with XX-YY instead of XX+YY. It is equivalent up to two single-qubit X rotations, but the reason to have it as a separate gate is that those extra single-qubit gates aren't necessary for the decomposition. The decomposition can be obtained from the XYGate decomposition by tweaking some signs in the gate angles.

An external reference for this gate is https://arxiv.org/abs/1208.1287.

I'm happy to contribute this gate if this proposal is accepted and the name agreed upon. I suggest PhasedXXMinusYYGate.

### Additional contract requirements

The new gate’s public class name is `XXMinusYYGate`, and it is exposed through the circuit library API.
