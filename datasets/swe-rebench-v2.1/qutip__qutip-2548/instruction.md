Bug in distributions.py concerning Qobj.data and Qobj.data_as()
### Bug Description

Hi, I think there is an bug in the distributions.py file. The functions `update_psi()` and  `update_rho()` of the class `TwoModeQuadratureCorrelation` both have a `Qobj.data[i,j]` type statement as was the norm before qutip5. I encountered this issue when code from my PC would not run on my MacBook. [HIDDEN]

### Code to Reproduce the Bug

```shell
import qutip as qt
a = qt.tensor(qt.destroy(5), qt.qeye(5))
b = qt.tensor(qt.qeye(5), qt.destroy(5))
z = 0.9
rho=qt.squeezing(a,b,z)*qt.tensor(qt.fock(5,0),qt.fock(5,0))
p=qt.TwoModeQuadratureCorrelation(rho,theta1=0,theta2=0)
p.visualize()
```


### Code Output

```shell
TypeError                                 Traceback (most recent call last)
Cell In[69], line 44
     39 print("P quadrature correlation:", p_corr)
     41 # Ensure the correct dimensions are used by TwoModeQuadratureCorrelation
     42 # Calculating two-mode quadrature correlation (if this is the function you mean)
     43 # This is a placeholder for any specific function you're calling:
---> 44 corr = qt.TwoModeQuadratureCorrelation(two_mode_squeezed_state)
     45 # print("Two-mode quadrature correlation:", corr)
File ~/Library/CloudStorage/OneDrive-ETHZurich/PythonScripts/Qutip/TMS_Kerr_simulations/.venv/lib/python3.12/site-packages/qutip/distributions.py:283, in TwoModeQuadratureCorrelation.__init__(self, state, theta1, theta2, extent, steps)
    280 self.theta1 = theta1
    281 self.theta2 = theta2
--> 283 self.update(state)
File ~/Library/CloudStorage/OneDrive-ETHZurich/PythonScripts/Qutip/TMS_Kerr_simulations/.venv/lib/python3.12/site-packages/qutip/distributions.py:291, in TwoModeQuadratureCorrelation.update(self, state)
    286 """
    287 calculate probability distribution for quadrature measurement
    288 outcomes given a two-mode wavefunction or density matrix
    289 """
    290 if isket(state):
--> 291     self.update_psi(state)
    292 else:
    293     self.update_rho(state)
...
    315         i = state_number_index([N, N], [n1, n2])
--> 316         p += kn1 * kn2 * psi.data[i, 0]
    318 self.data = abs(p) ** 2
TypeError: 'qutip.core.data.dense.Dense' object is not subscriptable
```


### Expected Behaviour

(<Figure size 800x600 with 2 Axes>,
 <Axes: xlabel='$X_1(\\theta_1)$', ylabel='$X_2(\\theta_2)$'>)
![image](https://github.com/user-attachments/assets/4087d55e-5f07-40bd-8b09-8869560817d7)


### Your Environment

```shell
QuTiP Version:      5.0.4
Numpy Version:      2.1.2
Scipy Version:      1.14.1
Cython Version:     None
Matplotlib Version: 3.9.2
Python Version:     3.12.5
Number of CPUs:     11
BLAS Info:          Generic
OPENMP Installed:   False

vs. on PC:

QuTiP Version:      4.7.2
Numpy Version:      1.25.2
Scipy Version:      1.11.1
Cython Version:     None
Matplotlib Version: 3.7.1
Python Version:     3.11.4
Number of CPUs:     24
BLAS Info:          INTEL MKL
OPENMP Installed:   False
```


### Additional Context

_No response_
