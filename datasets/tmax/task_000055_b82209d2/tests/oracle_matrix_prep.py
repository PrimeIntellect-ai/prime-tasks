import sys
import numpy as np

def process(filepath):
    A = np.loadtxt(filepath, delimiter=',')
    A_sym = (A + A.T) / 2.0
    w, v = np.linalg.eigh(A_sym)
    w_clipped = np.maximum(w, 1e-5)
    A_reg = v @ np.diag(w_clipped) @ v.T
    L = np.linalg.cholesky(A_reg)
    np.savetxt(sys.stdout, L, delimiter=',')

if __name__ == "__main__":
    process(sys.argv[1])
