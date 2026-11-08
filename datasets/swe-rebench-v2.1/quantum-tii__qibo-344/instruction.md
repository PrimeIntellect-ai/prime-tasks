Hamiltonian expectation for density matrices
**Describe the bug**
Hamiltonian expectation value calculation is wrong for density matrices, as they are treated as state vectors.

**To Reproduce**
```Python
import numpy as np
from qibo import hamiltonians

def random_density_matrix(nqubits):
    shape = 2 * (2 ** nqubits,)
    rho = np.random.random(shape) + 1j * np.random.random(shape)
    rho = rho + rho.T.conj()
    # Normalize
    ids = np.arange(2 ** nqubits)
    rho[ids, ids] = rho[ids, ids] / np.trace(rho)
    return rho


nqubits = 5
ham = hamiltonians.XXZ(nqubits)
state = random_density_matrix(nqubits)
print(ham.expectation(state))

matrix = np.array(ham.matrix)
# EV calculation for density matrices
print(np.trace(matrix @ state))
# EV calculation for state vectors
print(np.sum(np.conj(state) * (matrix @ state)))
```

**Expected behavior**
The calculated expectation value (first printed number) should agree with the `np.trace` calculation (second printed number) but instead it agrees with the third printed value, which is the formula for state vectors.
