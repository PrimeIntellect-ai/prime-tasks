#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_mcmc.py
import random

random.seed(42)
with open('/home/user/mcmc_results.tsv', 'w') as f:
    f.write("Iteration\tSequence\tScore\tAccepted\n")
    chars = ['A', 'C', 'G', 'T']
    for i in range(1, 2001):
        seq = "".join(random.choices(chars, k=30))
        score = random.randint(0, 100)
        accepted = 1 if random.random() > 0.4 else 0
        f.write(f"{i}\t{seq}\t{score}\t{accepted}\n")
EOF
    python3 /tmp/setup_mcmc.py

    chmod -R 777 /home/user
