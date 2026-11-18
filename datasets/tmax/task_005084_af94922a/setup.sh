#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas biopython

    mkdir -p /home/user

    # Run the setup script to generate the required files
    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# 1. Create Reference FASTA
reference_seq = "ATGCGTACGTTAGCTAGCTAGCTGATCGATCGTAGCTAGCTAGCTAGCATCGATCGATCGAGATTACAGATCGATCGATC"
with open('/home/user/reference.fasta', 'w') as f:
    f.write(">chr1\n")
    f.write(reference_seq + "\n")

# 2. Create Primers FASTA
primers = {
    "P1": "GATTACA",
    "P2": "CGATC",
    "P3": "AAAAA",
    "P4": "CTAACGTACG"
}

with open('/home/user/primers.fasta', 'w') as f:
    for pid, seq in primers.items():
        f.write(f">{pid}\n{seq}\n")

# 3. Create Melting Data
def generate_curve(T, L, k, Tm, b):
    return L / (1 + np.exp(-k * (T - Tm))) + b

np.random.seed(42)
temperatures = np.linspace(40, 90, 50)

with open('/home/user/melting_data.csv', 'w') as f:
    f.write("primer_id,temperature,fluorescence\n")

    # P1: Tm = 65.20
    f1 = generate_curve(temperatures, 100, 0.5, 65.20, 10) + np.random.normal(0, 0.5, len(temperatures))
    for t, fl in zip(temperatures, f1):
        f.write(f"P1,{t},{fl}\n")

    # P2: Tm = 60.00
    f2 = generate_curve(temperatures, 100, 0.5, 60.00, 10) + np.random.normal(0, 0.5, len(temperatures))
    for t, fl in zip(temperatures, f2):
        f.write(f"P2,{t},{fl}\n")

    # P3: Tm = 55.00
    f3 = generate_curve(temperatures, 100, 0.5, 55.00, 10) + np.random.normal(0, 0.5, len(temperatures))
    for t, fl in zip(temperatures, f3):
        f.write(f"P3,{t},{fl}\n")

    # P4: Tm = 68.45
    f4 = generate_curve(temperatures, 100, 0.5, 68.45, 10) + np.random.normal(0, 0.5, len(temperatures))
    for t, fl in zip(temperatures, f4):
        f.write(f"P4,{t},{fl}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
