Sampler fails on gates with unhashable parameters
### Environment

- **Qiskit Terra version**: fbff44bfe9ebc9d97203929b1bff5483fe06028a
- **Python version**: Python 3.10.8
- **Operating system**: Arch Linux


### What is happening?

See title.

### How can we reproduce the issue?

```python
import numpy as np

from qiskit.circuit import QuantumCircuit
from qiskit.extensions.unitary import UnitaryGate
from qiskit.primitives import Sampler

gate = UnitaryGate(np.eye(2))

circuit = QuantumCircuit(1)
circuit.append(gate, [0])
circuit.measure_all()

sampler = Sampler()
sampler_result = sampler.run([circuit]).result()
quasi_dists = sampler_result.quasi_dists
```
```
Traceback (most recent call last):
  File "/home/kjs/projects/qiskit-terra/scratch/sampler_hash_bug.py", line 14, in <module>
    sampler_result = sampler.run([circuit]).result()
  File "/home/kjs/projects/qiskit-terra/qiskit/primitives/base/base_sampler.py", line 184, in run
    return self._run(
  File "/home/kjs/projects/qiskit-terra/qiskit/primitives/sampler.py", line 146, in _run
    index = self._circuit_ids.get(key)
TypeError: unhashable type: 'numpy.ndarray'
```

### What should happen?

It should work.

### Any suggestions?

It appears the primitives rely on associating a hashable key with each circuit https://github.com/Qiskit/qiskit-terra/blob/514e38394657802e6cf4aefbf65fe3be3b23b783/qiskit/primitives/utils.py#L127. This is not working.
