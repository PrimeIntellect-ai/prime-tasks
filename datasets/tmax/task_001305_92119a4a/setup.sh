#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    pip3 install numpy scipy pandas biopython

    useradd -m -s /bin/bash user || true

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import random
import numpy as np

os.makedirs("/home/user", exist_ok=True)

# Generate FASTA
fasta_content = """>seq_alpha
MKVLL
>seq_beta
ACDEF
>seq_gamma
LMNOP
"""
with open("/home/user/sequences.fasta", "w") as f:
    f.write(fasta_content)

# Generate signals
np.random.seed(42)
random.seed(42)

params = {
    "seq_alpha": {"A": 2.5, "omega": 3.0, "phi": 1.0, "C": 0.5},
    "seq_beta": {"A": 1.2, "omega": 1.5, "phi": -0.5, "C": -0.2},
    "seq_gamma": {"A": 4.0, "omega": 5.0, "phi": 2.0, "C": 1.0},
}

rows = []
for seq_id, p in params.items():
    A = p["A"]
    omega = p["omega"]
    phi = p["phi"]
    C = p["C"]

    for t_idx in range(200):
        t = t_idx * 0.05
        val = A * np.sin(omega * t + phi) + C
        # Add tiny noise to make it realistic but not mess up the fit
        val += np.random.normal(0, 0.01)
        rows.append(f"{seq_id},{t_idx},{val:.6f}")

# Add a decoy sequence not in FASTA
for t_idx in range(200):
    rows.append(f"seq_decoy,{t_idx},0.000000")

random.shuffle(rows)

with open("/home/user/signals_raw.csv", "w") as f:
    f.write("seq_id,t_index,value\n")
    f.write("\n".join(rows) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
