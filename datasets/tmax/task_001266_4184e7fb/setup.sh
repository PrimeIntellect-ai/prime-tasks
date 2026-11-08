#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Create the input near-singular matrix
    python3 -c "
import numpy as np
np.random.seed(42)
V = np.random.rand(200, 200)
# Make it near singular
V[1] = V[0] + 1e-12
V[5] = V[0] * 2
np.save('/home/user/kmer_matrix.npy', V)
"

    # Create the buggy script
    cat << 'EOF' > /home/user/motif_nmf.py
import numpy as np

def run_nmf(V, k, iters):
    n, m = V.shape
    np.random.seed(42)
    W = np.random.rand(n, k)
    H = np.random.rand(k, m)

    for step in range(iters):
        # Update H
        WH = W @ H
        num_H = W.T @ V
        den_H = W.T @ WH
        for i in range(k):
            for j in range(m):
                H[i, j] = H[i, j] * (num_H[i, j] / den_H[i, j])

        # Update W
        WH = W @ H
        num_W = V @ H.T
        den_W = WH @ H.T
        for i in range(n):
            for j in range(k):
                W[i, j] = W[i, j] * (num_W[i, j] / den_W[i, j])

    return W, H

if __name__ == "__main__":
    V = np.load('/home/user/kmer_matrix.npy')
    W, H = run_nmf(V, 10, 50)
    np.save('/home/user/W_out.npy', W)
    np.save('/home/user/H_out.npy', H)
EOF

    chmod -R 777 /home/user
