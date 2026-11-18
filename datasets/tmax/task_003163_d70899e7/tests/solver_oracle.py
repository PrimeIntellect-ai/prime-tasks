import sys
import h5py
import numpy as np

def solve(hdf5_path):
    D = 4.15
    with h5py.File(hdf5_path, 'r') as f:
        data = f['/data/signal'][:]
        M = np.mean(data)

    # roots of x^3 + 0*x^2 + D*x - M = 0
    coeffs = [1.0, 0.0, D, -M]
    roots = np.roots(coeffs)
    real_roots = roots[np.isreal(roots)].real
    print(f"{real_roots[0]:.5f}")

if __name__ == "__main__":
    solve(sys.argv[1])
