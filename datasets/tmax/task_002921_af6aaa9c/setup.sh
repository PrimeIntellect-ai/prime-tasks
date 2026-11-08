#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import random
import os

random.seed(42)
# Create a biased transition matrix
transitions = {
    'A': ['A']*1 + ['C']*2 + ['G']*3 + ['T']*4,
    'C': ['A']*4 + ['C']*1 + ['G']*2 + ['T']*3,
    'G': ['A']*3 + ['C']*4 + ['G']*1 + ['T']*2,
    'T': ['A']*2 + ['C']*3 + ['G']*4 + ['T']*1,
}

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/sequences.fasta', 'w') as f:
    for s_idx in range(50):
        f.write(f">seq_{s_idx}\n")
        seq = ['A']
        for _ in range(2000):
            seq.append(random.choice(transitions[seq[-1]]))
        # Write sequence in chunks of 80
        for i in range(0, len(seq), 80):
            f.write("".join(seq[i:i+80]) + "\n")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
