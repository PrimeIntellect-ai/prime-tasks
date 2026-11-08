#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_task.py
import numpy as np

# 1. Generate FASTA
np.random.seed(123)
n_seqs = 100
seq_len = 100
base_seq = np.random.choice(['A', 'C', 'G', 'T'], size=seq_len)
with open('/home/user/data.fasta', 'w') as f:
    for i in range(n_seqs):
        # Mutate ~5% of bases
        mut = np.random.rand(seq_len) < 0.05
        current_seq = base_seq.copy()
        current_seq[mut] = np.random.choice(['A', 'C', 'G', 'T'], size=np.sum(mut))
        f.write(f">seq{i}\n")
        f.write("".join(current_seq) + "\n")

# 2. Generate mcmc_mutations.py
code = """import numpy as np
import time

def read_fasta(file_path):
    sequences = []
    with open(file_path, 'r') as f:
        seq = ""
        for line in f:
            if line.startswith(">"):
                if seq: sequences.append(seq)
                seq = ""
            else:
                seq += line.strip()
        if seq: sequences.append(seq)
    return sequences

def compute_distances(sequences):
    n = len(sequences)
    L = len(sequences[0])
    distances = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = sum(1 for a, b in zip(sequences[i], sequences[j]) if a != b)
            distances[i, j] = d
            distances[j, i] = d
    return distances

def likelihood(distances, mu, L):
    n = distances.shape[0]
    prob = 1.0
    for i in range(n):
        for j in range(i+1, n):
            d = distances[i, j]
            prob *= (mu**d) * ((1-mu)**(L-d))
    return prob

def run_mcmc(distances, L, iterations=1000, seed=42):
    np.random.seed(seed)
    mu_current = 0.5
    samples = []

    for _ in range(iterations):
        mu_proposal = np.random.normal(mu_current, 0.01)
        if mu_proposal <= 0.001 or mu_proposal >= 0.999:
            samples.append(mu_current)
            continue

        l_current = likelihood(distances, mu_current, L)
        l_proposal = likelihood(distances, mu_proposal, L)

        if l_current == 0:
            ratio = 1.0
        else:
            ratio = l_proposal / l_current

        if np.random.uniform(0, 1) < ratio:
            mu_current = mu_proposal
        samples.append(mu_current)

    return samples

if __name__ == "__main__":
    seqs = read_fasta("/home/user/data.fasta")
    t0 = time.time()
    dists = compute_distances(seqs)
    t1 = time.time()
    print(f"Distance matrix computed in {t1-t0:.4f} seconds.")

    samples = run_mcmc(dists, len(seqs[0]))
    print("MCMC finished. Posterior mean mu:", np.mean(samples))
"""
with open('/home/user/mcmc_mutations.py', 'w') as f:
    f.write(code)
EOF

    python3 /home/user/setup_task.py
    chmod -R 777 /home/user
