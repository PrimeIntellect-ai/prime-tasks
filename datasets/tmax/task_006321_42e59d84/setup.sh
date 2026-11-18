#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/ref.fasta
>seq1
ATGCGTACGTAGCTAGCTAGCTAGCTAG
>seq2
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAG
>seq3
ATGCGTACGTAGCTAG
>seq4
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAG
>seq5
ATGC
EOF

    cat << 'EOF' > /home/user/query.fasta
>q1
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
>q2
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
>q3
ATGCGTACGTAGCTAGCTAG
>q4
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
>q5
ATGCGTACGTAGCTAGCTAGCTAG
EOF

    cat << 'EOF' > /tmp/setup.py
import numpy as np

ref_lens = [28, 32, 16, 36, 4] # N_ref = 5
query_lens = [40, 44, 20, 48, 24] # N_query = 5
N_ref = len(ref_lens)
N_query = len(query_lens)
pooled = ref_lens + query_lens
N = len(pooled)

mean_ref = sum(ref_lens) / N_ref
mean_query = sum(query_lens) / N_query
D_obs = abs(mean_ref - mean_query)

state = 42

def xorshift32():
    global state
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17) & 0xFFFFFFFF
    state ^= (state << 5) & 0xFFFFFFFF
    return state

count = 0
permutations = 100000

for _ in range(permutations):
    arr = list(pooled)
    for i in range(N - 1, 0, -1):
        j = xorshift32() % (i + 1)
        arr[i], arr[j] = arr[j], arr[i]

    m_ref = sum(arr[:N_ref]) / N_ref
    m_query = sum(arr[N_ref:]) / N_query
    D_perm = abs(m_ref - m_query)

    # Use round to avoid floating point issues
    if round(D_perm, 6) >= round(D_obs, 6):
        count += 1

pvalue = count / permutations

with open('/home/user/.truth_pvalue.txt', 'w') as f:
    f.write(f"{pvalue:.4f}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
