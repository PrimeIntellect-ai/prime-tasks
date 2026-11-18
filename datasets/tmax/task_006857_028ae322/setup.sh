#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter numpy pandas matplotlib biopython

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import numpy as np

# Generate sequences.fasta
np.random.seed(42)
bases = np.array(['A', 'C', 'G', 'T'])
with open('/home/user/sequences.fasta', 'w') as f:
    for i in range(5):
        seq = "".join(np.random.choice(bases, size=500, p=[0.3, 0.2, 0.2, 0.3]))
        f.write(f">seq_{i}\n{seq}\n")

# Compute actual stable variances and generate reference_variances.csv with a slight deviation
# to make convergence happen at W=60
with open('/home/user/reference_variances.csv', 'w') as f:
    f.write("WindowSize,ReferenceVariance\n")
    for W in range(10, 110, 10):
        # Calculate true stable var
        all_gc = []
        with open('/home/user/sequences.fasta', 'r') as fasta:
            lines = fasta.readlines()
            seqs = [lines[i].strip() for i in range(1, len(lines), 2)]
            for seq in seqs:
                for j in range(len(seq) - W + 1):
                    window = seq[j:j+W]
                    gc = (window.count('G') + window.count('C')) / W
                    all_gc.append(gc)

        true_var = np.var(all_gc, ddof=0)

        # Add artificial noise to prevent convergence before W=60
        if W < 60:
            ref_var = true_var + 0.0001
        else:
            ref_var = true_var

        f.write(f"{W},{ref_var:.10f}\n")
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
