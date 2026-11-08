#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    echo -n "ACGTACGTACGTACGTACGTGCATGCATGCATGCATGCATTTAACCGGTTTTAACCGGTTGGCCAATTGGCCAATTGGCCTAGCTAGCTAGCTAGCTAGC" > /home/user/data/raw_reads.txt

    cat << 'EOF' > /home/user/mc_energy.py
import numpy as np
import concurrent.futures
import math

def compute_energy(sequence, seed=42):
    np.random.seed(seed)
    # generate 1000 random conformation arrays (multi-dimensional)
    conformations = np.random.randn(1000, 4, 20)

    # Sequence encoding
    seq_map = {'A':0, 'C':1, 'G':2, 'T':3}
    seq_encoded = np.array([seq_map[c] for c in sequence])

    def eval_conf(conf):
        val = 0.0
        for i in range(20):
            # Artificially create large magnitude differences to exacerbate fp errors
            val += conf[seq_encoded[i], i] * (10 ** (i % 7 - 3))
        return val

    total = 0.0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(eval_conf, conformations[i]) for i in range(1000)]
        for f in concurrent.futures.as_completed(futures):
            total += f.result()

    return total
EOF

    chmod -R 777 /home/user
