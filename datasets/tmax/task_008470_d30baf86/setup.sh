#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user/profiler_test
    cd /home/user/profiler_test

    # Generate a synthetic FASTA file
    cat << 'EOF' > generate_fasta.py
import random
random.seed(42)
with open("reads.fasta", "w") as f:
    for i in range(1, 51):
        seq = "".join(random.choices("ACGT", k=5000))
        f.write(f">seq_{i}\n{seq}\n")
EOF
    python3 generate_fasta.py
    rm generate_fasta.py

    # Create the slow script
    cat << 'EOF' > process.py
import numpy as np
from scipy.integrate import solve_ivp
import time

def read_fasta(file_path):
    seqs = {}
    with open(file_path, 'r') as f:
        curr_id = ""
        curr_seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs

def slow_moving_average_gc(seq, window=100):
    n = len(seq)
    gc_ratios = []
    for i in range(n - window + 1):
        subseq = seq[i:i+window]
        gc_count = sum(1 for base in subseq if base in "GC")
        gc_ratios.append(gc_count / window)
    return gc_ratios

def decay_ode(t, y, k):
    return -k * y

def main():
    start = time.time()
    seqs = read_fasta("reads.fasta")

    results = {}
    for seq_id, seq in seqs.items():
        gc_signal = slow_moving_average_gc(seq, window=100)
        max_gc = max(gc_signal) if gc_signal else 0.5

        sol = solve_ivp(decay_ode, [0, 10], [100.0], args=(max_gc,))
        final_c = sol.y[0][-1]
        results[seq_id] = final_c

    with open("final_concentrations.csv", "w") as f:
        f.write("SeqID,Final_C\n")
        for seq_id, final_c in results.items():
            f.write(f"{seq_id},{final_c:.5f}\n")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
