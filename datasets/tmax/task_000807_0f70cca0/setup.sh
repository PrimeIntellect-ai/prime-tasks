#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup.py
import numpy as np
import pandas as pd

np.random.seed(123)
W_true = np.random.rand(50, 3)
H_true = np.random.rand(3, 10)
V = W_true @ H_true
V += np.random.normal(0, 1e-6, V.shape) # Very small noise to ensure near-singularity for k=4

pd.DataFrame(V).to_csv('/home/user/gene_expression.csv', index=False, header=False)
EOF
    python3 setup.py
    rm setup.py

    cat << 'EOF' > als_nmf.py
import numpy as np
import pandas as pd

def als_nmf(V, k, max_iter=1000):
    np.random.seed(42)
    n, m = V.shape
    W = np.random.rand(n, k)
    H = np.random.rand(k, m)

    for i in range(max_iter):
        # Update H: H = (W^T W)^-1 W^T V
        H = np.linalg.solve(W.T @ W, W.T @ V)
        H[H < 0] = 0

        # Update W: W^T = (H H^T)^-1 H V^T
        W = np.linalg.solve(H @ H.T, H @ V.T).T
        W[W < 0] = 0

    return W, H

if __name__ == "__main__":
    V = pd.read_csv('/home/user/gene_expression.csv', header=None).values
    W, H = als_nmf(V, k=3)
    print("Done k=3")
    W, H = als_nmf(V, k=4)
    print("Done k=4")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
