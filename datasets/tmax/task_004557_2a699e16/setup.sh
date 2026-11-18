#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential pkg-config libhdf5-dev
    pip3 install pytest h5py numpy

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH=/usr/local/cargo/bin:$PATH

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/networks.txt
1 4 0,1;1,2;2,3;3,0
2 5 0,1;0,2;0,3;0,4
3 6 0,1;1,2;2,3;3,4;4,5
EOF

    cat << 'EOF' > /home/user/validate.py
import h5py
import numpy as np
import sys

def simulate_star(n, p=0.3, iters=50000):
    np.random.seed(42)
    times = []
    for _ in range(iters):
        t = 0
        infected = 1
        while infected < n:
            t += 1
            # n-1 nodes, each has probability p of being infected each step
            # We track number of remaining susceptible
            sus = n - infected
            new_inf = np.random.binomial(sus, p)
            infected += new_inf
        times.append(t)
    return np.mean(times)

def main():
    try:
        f = h5py.File('/home/user/training_data.h5', 'r')
        mean_times = f['mean_times'][:]
    except Exception as e:
        print(f"Failed to read HDF5: {e}")
        sys.exit(1)

    if len(mean_times) != 3:
        print(f"Expected 3 values, got {len(mean_times)}")
        sys.exit(1)

    # Expected values approximated via high N monte carlo or exact markov chain
    # Allow a generous tolerance (e.g. +/- 0.5) due to MC variance of 5000 runs

    # Graph 2 is a star graph with 4 leaves.
    # Expected time is max of 4 geometric random variables with p=0.3
    # E[max(G1, G2, G3, G4)] where G_i ~ Geom(0.3) is approx 6.06
    val_g2 = mean_times[1]

    if not (5.5 <= val_g2 <= 6.5):
        print(f"Graph 2 mean time {val_g2} is out of expected range [5.5, 6.5].")
        sys.exit(1)

    # Graph 3 is a line graph of 6 nodes. Distance is 5.
    # Sum of 5 Geometrics with p=0.3 -> Expected time = 5 / 0.3 = 16.666
    val_g3 = mean_times[2]
    if not (15.5 <= val_g3 <= 17.5):
        print(f"Graph 3 mean time {val_g3} is out of expected range [15.5, 17.5].")
        sys.exit(1)

    print("Validation passed.")
    sys.exit(0)

if __name__ == '__main__':
    main()
EOF

    chmod 644 /home/user/networks.txt
    chmod +x /home/user/validate.py
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo
    chmod -R 777 /usr/local/rustup
