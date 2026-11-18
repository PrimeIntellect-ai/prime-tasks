#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy cython setuptools

    mkdir -p /app/poly_basis
    cat << 'EOF' > /app/poly_basis/poly_basis.pyx
import numpy as np
cimport numpy as np

def expand(np.ndarray[np.float64_t, ndim=1] x, int degree):
    cdef list out = []
    cdef int i, d
    for i in range(x.shape[0]):
        for d in range(1, degree + 1):
            out.append(x[i] ** d)
    return np.array(out, dtype=np.float64)
EOF

    cat << 'EOF' > /app/poly_basis/setup.py
from setuptools import setup, Extension
import numpy as np

setup(
    name="poly_basis",
    version="1.0.0",
    ext_modules=[Extension("poly_basis", ["poly_basis.c"])],
    include_dirs=[np.get_include()]
)
EOF

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os
os.makedirs('/app/data', exist_ok=True)
np.random.seed(42)
W = np.random.randn(1000, 18) 
np.save('/app/data/posterior_weights.npy', W)

A = np.random.randn(18, 18)
S = A @ A.T + np.eye(18) * 1e-3
np.save('/app/data/scale_matrix.npy', S)
EOF
    python3 /tmp/generate_data.py

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/run_model_oracle
#!/usr/bin/env python3
import sys
import numpy as np
import scipy.linalg
from poly_basis import expand

def main():
    args = [float(a) for a in sys.argv[1:]]
    x = np.array(args, dtype=np.float64)
    x_poly = expand(x, 3)

    W = np.load('/app/data/posterior_weights.npy')
    S = np.load('/app/data/scale_matrix.npy')

    dim = len(x_poly)
    W = W[:, :dim]
    S = S[:dim, :dim]

    L = scipy.linalg.cholesky(S, lower=True)
    z = scipy.linalg.solve_triangular(L, x_poly, lower=True)

    y_preds = W @ z

    seed = int(np.sum(np.abs(x)) * 1000)
    rng = np.random.default_rng(seed)

    medians = np.zeros(2000)
    for i in range(2000):
        resample = rng.choice(y_preds, size=len(y_preds), replace=True)
        medians[i] = np.median(resample)

    p25 = np.percentile(medians, 2.5)
    p975 = np.percentile(medians, 97.5)
    mean_val = np.mean(y_preds)

    print(f"Mean: {mean_val:.4f}, CI: [{p25:.4f}, {p975:.4f}]")

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/run_model_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
