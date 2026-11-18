#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    mkdir -p /home/user

    # Generate the sequence dataset
    cat << 'EOF' > /home/user/generate_fasta.py
import random

random.seed(42)
with open("/home/user/sequences.fasta", "w") as f:
    for i in range(1, 101):
        seq_id = f"SEQ_{i:03d}"
        seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=500))
        f.write(f">{seq_id}\n{seq}\n")
EOF
    python3 /home/user/generate_fasta.py
    rm /home/user/generate_fasta.py

    # Create the buggy Python script
    cat << 'EOF' > /home/user/mutation_sim.py
import concurrent.futures
import numpy as np
import sys

def simulate_mutations(seq_id, sequence):
    # Deterministic Monte Carlo simulation per sequence
    # Hash is kept consistent by taking the numeric part of SEQ_XXX
    numeric_id = int(seq_id.split('_')[1])
    np.random.seed(numeric_id)

    mutations = 0.0
    for char in sequence:
        if char == 'A': mutations += np.random.uniform(0, 0.01)
        elif char == 'C': mutations += np.random.uniform(0, 0.02)
        elif char == 'G': mutations += np.random.uniform(0, 0.015)
        elif char == 'T': mutations += np.random.uniform(0, 0.005)
    return seq_id, mutations

def main():
    sequences = {}
    with open("/home/user/sequences.fasta", "r") as f:
        curr_id = ""
        for line in f:
            if line.startswith(">"):
                curr_id = line.strip()[1:]
                sequences[curr_id] = ""
            else:
                sequences[curr_id] += line.strip()

    total_burden = 0.0

    # BUG: Non-deterministic floating point reduction
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(simulate_mutations, sid, seq): sid for sid, seq in sequences.items()}
        for future in concurrent.futures.as_completed(futures):
            _, burden = future.result()
            total_burden += burden

    with open("/home/user/reproducible_result.txt", "w") as f:
        f.write(f"{total_burden:.15f}\n")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
