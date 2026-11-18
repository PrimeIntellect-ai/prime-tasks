#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate dataset
    cat << 'EOF' > /tmp/generate_dataset.py
import random
import os

os.makedirs('/home/user', exist_ok=True)
random.seed(42)
seqs = []
bases = ['A', 'C', 'G', 'T']
for _ in range(10000):
    seqs.append(''.join(random.choices(bases, k=50)))

# Plant a close pair at known indices
target_index1 = 42
target_index2 = 1337

# Copy and mutate 2 positions
s = list(seqs[target_index1])
s[10] = 'A' if s[10] != 'A' else 'C'
s[20] = 'G' if s[20] != 'G' else 'T'
seqs[target_index2] = ''.join(s)

with open('/home/user/dataset.txt', 'w') as f:
    for seq in seqs:
        f.write(seq + '\n')
EOF

    python3 /tmp/generate_dataset.py

    # Set permissions
    chmod -R 777 /home/user
