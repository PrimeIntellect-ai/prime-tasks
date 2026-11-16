Dimension mismatch in solving energy restricted eigenstates
### Bug Description

Calling `Qobj.eigenstates()` of an operator created with energy restricted functionality raises an error. I believe this is due to the dimension refactoring of v5. [HIDDEN]

### Code to Reproduce the Bug

```shell
# Hamiltonian of two uncoupled qubits (harmonic oscillators limited to 2 levels) with energies e1 and e2, and only one excitation allowed in the system.

import qutip as qt
dims = [2, 2]
excitations = 1
e1, e2 = 1, 2
a1, a2 = qt.enr_destroy(dims, excitations)
H = e1*a1.dag()*a1 + e2*a2.dag()*a2
H.eigenstates()
```


### Code Output

```shell
ValueError                                Traceback (most recent call last)
Cell In[3], line 6
      4 a1, a2 = qt.enr_destroy(dims, excitations)
      5 H = e1*a1.dag()*a1 + e2*a2.dag()*a2
----> 6 H.eigenstates()

File ~\anaconda3\envs\bare_qt5\Lib\site-packages\qutip\core\qobj.py:1514, in Qobj.eigenstates(self, sparse, sort, eigvals, tol, maxiter, phase_fix)
   1512     new_dims = [self.dims[0], [1]*len(self.dims[0])]
   1513 ekets = np.empty((evecs.shape[1],), dtype=object)
-> 1514 ekets[:] = [Qobj(vec, dims=new_dims, copy=False)
   1515             for vec in _data.split_columns(evecs, False)]
   1516 norms = np.array([ket.norm() for ket in ekets])
   1517 if phase_fix is None:

File ~\anaconda3\envs\bare_qt5\Lib\site-packages\qutip\core\qobj.py:279, in Qobj.__init__(self, arg, dims, copy, superrep, isherm, isunitary)
    277 self._isherm = isherm
    278 self._isunitary = isunitary
--> 279 self._initialize_data(arg, dims, copy)
    281 if superrep is not None:
    282     self.superrep = superrep

File ~\anaconda3\envs\bare_qt5\Lib\site-packages\qutip\core\qobj.py:265, in Qobj._initialize_data(self, arg, dims, copy)
    261     self._dims = Dimensions(
    262         dims or [[self._data.shape[0]], [self._data.shape[1]]]
    263     )
    264 if self._dims.shape != self._data.shape:
--> 265     raise ValueError('Provided dimensions do not match the data: ' +
    266                      f"{self._dims.shape} vs {self._data.shape}")

ValueError: Provided dimensions do not match the data: (np.int64(4), np.int64(1)) vs (3, 1)
```


### Expected Behaviour

I expect v5 to work like v4.7.5, where the same code gives the following output:
```
(array([0., 1., 2.]),
 array([Quantum object: dims = [[2, 2], [1, 1]], shape = (3, 1), type = ket
        Qobj data =
        [[1.]
         [0.]
         [0.]]                                                             ,
        Quantum object: dims = [[2, 2], [1, 1]], shape = (3, 1), type = ket
        Qobj data =
        [[0.]
         [0.]
         [1.]]                                                             ,
        Quantum object: dims = [[2, 2], [1, 1]], shape = (3, 1), type = ket
        Qobj data =
        [[0.]
         [1.]
         [0.]]                                                             ],
       dtype=object))
```


### Your Environment

```shell
QuTiP Version:      5.1.0
Numpy Version:      2.2.1
Scipy Version:      1.15.0
Cython Version:     None
Matplotlib Version: 3.10.0
Python Version:     3.12.8
Number of CPUs:     8
BLAS Info:          Generic
INTEL MKL Ext:      None
Platform Info:      Windows (AMD64)
```


### Additional Context

Contributing to the Qutip community is new territory for me, so please bare with me as learn the ropes. I'm happy to create a PR with additional testing for this issue, if the suggested solution seems reasonable.

### Additional contract requirements

- For the reproduced energy-restricted Hamiltonian, `Qobj.eigenstates()` must return the complete spectrum and corresponding eigenvectors.
- Each returned eigenvector must have dimensions compatible with the reduced energy-restricted operator and be usable in its eigenvalue equation.
