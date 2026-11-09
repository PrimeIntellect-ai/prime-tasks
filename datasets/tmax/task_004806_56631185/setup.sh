#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy biopython

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

fasta_content = \"\"\">seq1
ATGCGTACGTTAGCTAGCTAAGCGATC
>seq2
ATGCGTACGTTAGCTAGCTAAGCGATC
>seq3
ATGCGTACGTTACCTAGCTAAGCGATC
>seq4
ATGCGTACGTTAGCTAGCTCAGCGATC
>seq5
ATGCGTACGTTAGCTAGCTAAGCGATC
\"\"\"
with open('/home/user/sequences.fasta', 'w') as f:
    f.write(fasta_content)

t = np.linspace(0, 30, 31)
F0 = 2.5
r_true = 0.45
K_true = 120.0

def logistic(t, r, K, F0):
    return K / (1 + (K/F0 - 1)*np.exp(-r*t))

F_data = logistic(t, r_true, K_true, F0)

df = pd.DataFrame({'time': t, 'fluorescence': F_data})
df.to_csv('/home/user/kinetic_data.csv', index=False)
"

    chmod -R 777 /home/user
