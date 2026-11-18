#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/gene.fasta
>gene1
ATGCATGCATGCATGCATGCATGCATGCATGCATGCATGC
EOF

    cat << 'EOF' > /home/user/simulate.py
import numpy as np
import matplotlib.pyplot as plt

def get_gc_content(fasta_path):
    with open(fasta_path, 'r') as f:
        seq = ''.join([line.strip() for line in f if not line.startswith('>')])
    gc = sum(1 for c in seq if c in 'GCgc')
    return gc / len(seq) if len(seq) > 0 else 0

def simulate():
    gc = get_gc_content('/home/user/gene.fasta')
    k_tx = gc * 10.0
    k_deg_m = 1000.0
    k_tl = 10.0
    k_deg_p = 0.1

    dt = 0.1
    t = np.arange(0, 10 + dt, dt)
    mRNA = np.zeros(len(t))
    Protein = np.zeros(len(t))

    for i in range(1, len(t)):
        mRNA[i] = mRNA[i-1] + dt * (k_tx - k_deg_m * mRNA[i-1])
        Protein[i] = Protein[i-1] + dt * (k_tl * mRNA[i-1] - k_deg_p * Protein[i-1])

    return t, Protein

if __name__ == '__main__':
    t, p = simulate()
    with open('/home/user/final_protein.txt', 'w') as f:
        f.write(f"{p[-1]:.4f}\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
