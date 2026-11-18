#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np

# Generate reference data
np.random.seed(42)
W_true = np.random.rand(100, 5)
H_true = np.random.rand(5, 50)
V = W_true @ H_true
np.savetxt('/home/user/reference.csv', V, delimiter=',')

# Generate noisy data with zeros to induce instability
V_noisy = V + np.random.normal(0, 0.1, V.shape)
V_noisy = np.clip(V_noisy, 0, None)
V_noisy[10, :] = 0
np.savetxt('/home/user/noisy_data.csv', V_noisy, delimiter=',')
EOF

    python3 generate_data.py

    cat << 'EOF' > mf.py
import numpy as np

def nmf(V, k, max_iter=1000):
    np.random.seed(0)
    n, m = V.shape
    W = np.random.rand(n, k)
    H = np.random.rand(k, m)

    for _ in range(max_iter):
        # Multiplicative updates
        H = H * (W.T @ V) / (W.T @ W @ H)
        W = W * (V @ H.T) / (W @ H @ H.T)

    return W, H

if __name__ == "__main__":
    V = np.loadtxt('/home/user/noisy_data.csv', delimiter=',')
    W, H = nmf(V, k=5)
    V_rec = W @ H
    print("Reconstruction complete.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
