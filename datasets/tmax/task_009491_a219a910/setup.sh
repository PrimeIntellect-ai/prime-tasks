#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

def generate_reference(N, seed, filename):
    rng = np.random.default_rng(seed)
    samples = []
    while len(samples) < N:
        batch = rng.uniform(-1, 1, size=(N, 3))
        u = rng.uniform(0, 3, size=N)
        f_val = np.sum(batch**2, axis=1)
        accepted = batch[u < f_val]
        samples.extend(accepted)
    samples = np.array(samples)[:N]

    with open(filename, 'w') as f:
        f.write("x,y,z\n")
        for row in samples:
            f.write(f"{row[0]},{row[1]},{row[2]}\n")

generate_reference(100000, 999, '/home/user/reference_100000.csv')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
