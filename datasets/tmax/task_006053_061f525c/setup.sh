#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

def generate_data():
    np.random.seed(42)
    N_total = 3000
    true_mu_x = 65.2
    true_mu_y = 35.8
    true_sigma = 4.5
    true_w = 0.6

    N_cluster = int(N_total * true_w)
    N_bg = N_total - N_cluster

    # Generate cluster points
    cluster_x = np.random.normal(true_mu_x, true_sigma, N_cluster)
    cluster_y = np.random.normal(true_mu_y, true_sigma, N_cluster)

    # Generate background points
    bg_x = np.random.uniform(0, 100, N_bg)
    bg_y = np.random.uniform(0, 100, N_bg)

    x = np.concatenate([cluster_x, bg_x])
    y = np.concatenate([cluster_y, bg_y])

    # Filter out out-of-bounds points to strictly follow the model domain
    mask = (x >= 0) & (x <= 100) & (y >= 0) & (y <= 100)
    x = x[mask]
    y = y[mask]

    # Shuffle
    idx = np.random.permutation(len(x))
    x = x[idx]
    y = y[idx]

    with h5py.File('/home/user/star_data.h5', 'w') as f:
        f.create_dataset('x', data=x)
        f.create_dataset('y', data=y)

if __name__ == "__main__":
    generate_data()
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
