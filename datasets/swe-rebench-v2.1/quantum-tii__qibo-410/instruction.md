Imaginary values in symbolic hamiltonians
An error appears when defining the Hamiltonian with imaginary values in the symbolic representation.

Code to reproduce the behavior:
```
import numpy as np
from qibo import gates, hamiltonians, models, matrices, callbacks
import sympy


def Z_hamiltonian(N, L, t, r=1):
    nqubits = N*L

    # Define Hamiltonian using these symbols
    Z = sympy.symbols(" ".join((f"Z{i}" for i in range(nqubits))))
    X = sympy.symbols(" ".join((f"X{i}" for i in range(nqubits))))
    Y = sympy.symbols(" ".join((f"Y{i}" for i in range(nqubits))))
    sigma_plus = [0.5*X[i] + 0.5j*Y[i] for i in range(nqubits)]
    sigma_minus = [0.5*X[i] - 0.5j*Y[i] for i in range(nqubits)]

    # Define a map from symbols to actual matrices
    symbol_map = {s: (i, matrices.X) for i, s in enumerate(X)}
    symbol_map.update({s: (i, matrices.Z) for i, s in enumerate(Z)})
    symbol_map.update({s: (i, matrices.Y) for i, s in enumerate(Y)})

    # Define a dense Hamiltonian
    symbolic_ham = 0
    for s in range(N):
        for i in range(L):
            for rr in range(1,r+1):
                temp1 = (sigma_plus[i+s*L]*sigma_minus[(i+rr)%L+s*L] + sigma_minus[i+s*L]*sigma_plus[(i+rr)%L+s*L])
                for j in range(min(i, (i+rr)%L)+1, max(i, (i+rr)%L)):
                    temp1 *= Z[j+s*L]
                symbolic_ham -= t*temp1

    print(sympy.simplify(symbolic_ham))
    return hamiltonians.Hamiltonian.from_symbolic(symbolic_ham, symbol_map)

N = 2
L = 3
t = 1j
hamiltonian_jw = Z_hamiltonian(N=N, L=L, t=t)
```
If you put t=1 it works perfectly, but when I define it as a complex number I get an error.
In case it is a bug, can be fixed asap? Thank you!
