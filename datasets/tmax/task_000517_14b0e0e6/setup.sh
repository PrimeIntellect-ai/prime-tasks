#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
AATGC
>seq2
CCG
>seq3
GGT
>seq4
TTAA
EOF

    cat << 'EOF' > /home/user/reference_weights.csv
Feature,ReferenceWeight
A,0.50
C,0.20
G,0.80
T,0.40
EOF

    cat << 'EOF' > /home/user/mcmc_regression.py
import numpy as np

def parse_fasta(filepath):
    seqs = []
    with open(filepath) as f:
        seq = ""
        for line in f:
            if line.startswith(">"):
                if seq: seqs.append(seq)
                seq = ""
            else:
                seq += line.strip()
        if seq: seqs.append(seq)
    return seqs

np.random.seed(42)
seqs = parse_fasta('/home/user/sequences.fasta')

# Target variable (mock binding affinities)
y = np.array([2.5, 1.2, 2.0, 1.8])

# Extract features: A, C, G, T counts and Length
X = []
for s in seqs:
    X.append([s.count('A'), s.count('C'), s.count('G'), s.count('T'), len(s)])
X = np.array(X)

# Initialize MCMC using MLE (causes singular matrix error due to Length = A+C+G+T)
beta_init = np.linalg.inv(X.T @ X) @ X.T @ y

# Metropolis-Hastings MCMC
n_iter = 10000
beta = np.copy(beta_init)
samples = np.zeros((n_iter, X.shape[1]))

for i in range(n_iter):
    proposal = beta + np.random.normal(0, 0.1, size=beta.shape)

    # Log-likelihood (assuming normal errors with variance 1)
    ll_current = -0.5 * np.sum((y - X @ beta)**2)
    ll_proposal = -0.5 * np.sum((y - X @ proposal)**2)

    # Flat priors, so acceptance ratio only depends on likelihood
    if np.log(np.random.uniform()) < (ll_proposal - ll_current):
        beta = proposal

    samples[i, :] = beta

# Burn-in and posterior mean
burn_in = 2000
posterior_means = np.mean(samples[burn_in:, :], axis=0)

print("Posterior means:")
for i, name in enumerate(['A', 'C', 'G', 'T', 'Length']):
    if i < len(posterior_means):
         print(f"{name}: {posterior_means[i]:.4f}")
EOF

    chmod -R 777 /home/user
