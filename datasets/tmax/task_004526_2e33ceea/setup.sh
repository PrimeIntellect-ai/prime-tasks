#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy setuptools

    # Create vendored package structure
    mkdir -p /app/vendored/struct-stats-1.1.0/struct_stats

    cat << 'EOF' > /app/vendored/struct-stats-1.1.0/setup.py
from setuptools import setup, find_packages
setup(
    name='struct-stats',
    version='1.1.0',
    packages=find_packages(),
    install_requires=['numpy==0.1.0'] # PERTURBATION
)
EOF

    touch /app/vendored/struct-stats-1.1.0/struct_stats/__init__.py

    cat << 'EOF' > /app/vendored/struct-stats-1.1.0/struct_stats/hypothesis.py
import numpy as np
def permutation_test(dist_a, dist_b, n_permutations=5000):
    np.random.seed(123) # internal seed for reproducibility of permutations
    diff_obs = np.mean(dist_b) - np.mean(dist_a)
    combined = np.concatenate([dist_a, dist_b])
    count = 0
    n_a = len(dist_a)
    for _ in range(n_permutations):
        np.random.shuffle(combined)
        diff_perm = np.mean(combined[n_a:]) - np.mean(combined[:n_a])
        if diff_perm >= diff_obs:
            count += 1
    p_value = count / n_permutations
    return float(diff_obs), float(p_value)
EOF

    # Create data directory and reference PDB file
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/reference.pdb
ATOM      1  CA  ALA A   1      11.104  13.727  15.000  1.00  0.00           C
ATOM      2  CA  ALA A   2      14.104  15.727  16.000  1.00  0.00           C
ATOM      3  CA  ALA A   3      17.104  17.727  17.000  1.00  0.00           C
ATOM      4  CA  ALA A   4      20.104  19.727  18.000  1.00  0.00           C
ATOM      5  CA  ALA A   5      23.104  21.727  19.000  1.00  0.00           C
ATOM      6  CA  ALA A   6      26.104  23.727  20.000  1.00  0.00           C
ATOM      7  CA  ALA A   7      29.104  25.727  21.000  1.00  0.00           C
ATOM      8  CA  ALA A   8      32.104  27.727  22.000  1.00  0.00           C
ATOM      9  CA  ALA A   9      35.104  29.727  23.000  1.00  0.00           C
ATOM     10  CA  ALA A  10      38.104  31.727  24.000  1.00  0.00           C
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/vendored
