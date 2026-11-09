#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import random

random.seed(42)
with open('/home/user/primers.fasta', 'w') as f:
    for i in range(200):
        # Generate lengths between 18 and 24
        length = random.randint(18, 24)
        # Bias GC content to make the distribution interesting (bimodal)
        if random.random() < 0.6:
            gc_prob = random.uniform(0.3, 0.45)
        else:
            gc_prob = random.uniform(0.55, 0.7)

        seq = []
        for _ in range(length):
            if random.random() < gc_prob:
                seq.append(random.choice(['G', 'C']))
            else:
                seq.append(random.choice(['A', 'T']))
        f.write(f">primer_{i}\n{''.join(seq)}\n")
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
