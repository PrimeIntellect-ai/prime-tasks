#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mc_energy.py
import random
import math
from multiprocessing import Pool

def simulate_mutations(args):
    seq, seed = args
    random.seed(seed)
    # Simulate thermal noise impact based on sequence length
    energy = len(seq) * 0.01
    for _ in range(100):
        energy += random.uniform(-0.1, 0.1) * math.pi
    return energy

def get_expected_energy(seq, num_trials=500):
    args = [(seq, i) for i in range(num_trials)]
    total_energy = 0.0
    with Pool(4) as p:
        for res in p.imap_unordered(simulate_mutations, args):
            total_energy += res
    return total_energy / num_trials
EOF

    chmod -R 777 /home/user
