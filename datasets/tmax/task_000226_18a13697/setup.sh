#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import random
import math
import os

random.seed(42)

num_sequences = 500000
seq_length = 50
bases = ['A', 'C', 'G', 'T']
weights_bg = [0.25, 0.25, 0.25, 0.25]
weights_at = [0.35, 0.15, 0.15, 0.35]

log_ratios = {
    'A': math.log(0.30 / 0.25),
    'T': math.log(0.30 / 0.25),
    'C': math.log(0.20 / 0.25),
    'G': math.log(0.20 / 0.25)
}

significant_count = 0

with open('/home/user/sequences.txt', 'w') as f:
    for i in range(num_sequences):
        if random.random() < 0.1:
            seq = random.choices(bases, weights=weights_at, k=seq_length)
        else:
            seq = random.choices(bases, weights=weights_bg, k=seq_length)

        seq_str = "".join(seq)
        f.write(seq_str + "\n")

        llr = sum(log_ratios[b] for b in seq_str)
        if llr > 5.0:
            significant_count += 1

with open('/tmp/expected_count.txt', 'w') as f:
    f.write(str(significant_count))
EOF

    python3 /tmp/generate_data.py
    chmod 777 /tmp/expected_count.txt
    chmod -R 777 /home/user
