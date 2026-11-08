#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy h5py

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import h5py
import numpy as np

os.makedirs("/app", exist_ok=True)

# 1. Create HDF5 file
np.random.seed(123)
data = np.random.randn(100, 50000).astype(np.float32) * 0.1 + 0.5
with h5py.File("/app/sim_results.h5", "w") as f:
    f.create_dataset("trials", data=data)

# 2. Create PDB file
pdb_content = """ATOM      1  N   ALA A   1      -0.525   1.362   0.000  1.00  0.00           N  
ATOM      2  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      3  C   ALA A   1       1.520   0.000   0.000  1.00  0.00           C  
"""
carbons = "\n".join([f"ATOM   {i:4d}  C   ALA A   1       1.520   0.000   0.000  1.00  0.00           C  " for i in range(4, 44)])
with open("/app/molecule.pdb", "w") as f:
    f.write(pdb_content + carbons + "\n")

# 3. Audio file
os.system('echo "The cooling rate is 0.015" | espeak -w /app/experiment_log.wav')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
