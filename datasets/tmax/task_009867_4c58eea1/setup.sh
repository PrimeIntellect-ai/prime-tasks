#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import csv
import random
import math

random.seed(42)
alpha_true = 2.0
beta_true = 0.1

with open('/home/user/sequences.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['Day', 'Sequence'])
    for day in range(1, 31):
        # M(t) = (alpha/beta) * (1 - exp(-beta * t))
        expected_M = (alpha_true / beta_true) * (1 - math.exp(-beta_true * day))
        for _ in range(5): # 5 sequences per day
            actual_M = max(0, int(random.gauss(expected_M, 1.0)))
            seq = ['A'] * 50
            # Mutate 'actual_M' distinct positions to 'T'
            positions = random.sample(range(50), min(actual_M, 50))
            for pos in positions:
                seq[pos] = 'T'
            writer.writerow([day, "".join(seq)])
EOF

    python3 /home/user/generate_data.py

    chmod -R 777 /home/user
