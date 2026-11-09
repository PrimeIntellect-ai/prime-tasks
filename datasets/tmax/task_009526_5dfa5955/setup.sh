#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv openmpi-bin libopenmpi-dev
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_reference.py
import numpy as np

all_samples = []
for rank in range(4):
    rng = np.random.default_rng(seed=rank)
    samples = rng.standard_normal(10000)
    all_samples.append(samples)

all_samples = np.concatenate(all_samples)
shifted_samples = all_samples + 0.05

np.savetxt('/home/user/reference_data.txt', shifted_samples)
EOF
    python3 /home/user/setup_reference.py
    rm /home/user/setup_reference.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
