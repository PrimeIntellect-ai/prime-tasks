#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest nbformat

    mkdir -p /home/user
    cd /home/user

    # Create the DNA sequence
    echo "ACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACGACG" > /home/user/sequence.txt

    # Create the python script to generate the notebook
    cat << 'EOF' > /home/user/create_nb.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code_cell_1 = """\
# Parameters
valA = 1
valC = 2
valG = 3
valT = 4
"""

code_cell_2 = """\
import numpy as np

with open('/home/user/sequence.txt', 'r') as f:
    seq = f.read().strip()

mapping = {'A': valA, 'C': valC, 'G': valG, 'T': valT}
num_seq = np.array([mapping.get(base, 0) for base in seq])

N = len(num_seq)
fft_vals = np.abs(np.fft.fft(num_seq))**2

# Find the index closest to N/3
target_idx = int(np.round(N / 3.0))

# Score is the power at N/3 divided by the average power
signal = fft_vals[target_idx]
noise = np.mean(fft_vals[1:]) # exclude DC component

score = signal / noise if noise > 0 else 0

with open('/home/user/current_score.txt', 'w') as f:
    f.write(str(score))
"""

nb['cells'] = [nbf.v4.new_code_cell(code_cell_1), nbf.v4.new_code_cell(code_cell_2)]
nb.cells[0].metadata["tags"] = ["parameters"]

nbf.write(nb, '/home/user/calc_fft.ipynb')
EOF

    # Generate the notebook
    python3 /home/user/create_nb.py

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
