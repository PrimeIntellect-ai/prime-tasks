#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy pandas

cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

t = np.array([0, 5, 10, 15, 20, 25, 30])
k_A, k_B, k_C = 0.05, 0.012, 0.09

M_A = 1 - np.exp(-k_A * t)
M_B = 1 - np.exp(-k_B * t)
M_C = 1 - np.exp(-k_C * t)

with open('/home/user/viral_samples.csv', 'w') as f:
    f.write("time_days,region_A_mut_freq,region_B_mut_freq,region_C_mut_freq\n")
    for i in range(len(t)):
        f.write(f"{t[i]},{M_A[i]:.4f},{M_B[i]:.4f},{M_C[i]:.4f}\n")

np.random.seed(42)
seq = np.random.choice(['A', 'C', 'G', 'T'], size=1000)
seq[300:400] = np.random.choice(['A', 'T'], size=100)
perfect_primer = list("ATCGATCGATCGATCGATCG")
seq[325:345] = perfect_primer

fasta_content = ">NC_000001.1 Viral Reference Genome\n" + "".join(seq) + "\n"
with open('/home/user/reference.fasta', 'w') as f:
    f.write(fasta_content)
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
