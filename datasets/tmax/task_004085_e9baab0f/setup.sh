#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep
    pip3 install pytest

    mkdir -p /app
    touch /app/run_sim
    chmod +x /app/run_sim

    cat << 'EOF' > /tmp/gen.py
import os
import random

os.makedirs('/home/user/data/clean', exist_ok=True)
os.makedirs('/home/user/data/evil', exist_ok=True)

valid_aa = list("ACDEFGHIKLMNPQRSTVWY")
gc_aa = list("GCPW")
non_gc_aa = [a for a in valid_aa if a not in gc_aa]

def make_clean(length=100):
    seq = []
    for _ in range(length):
        if random.random() < 0.4:
            seq.append(random.choice(gc_aa))
        else:
            seq.append(random.choice(non_gc_aa))
    return "".join(seq)

for i in range(50):
    with open(f'/home/user/data/clean/clean_{i}.fasta', 'w') as f:
        f.write(f">clean_{i}\n{make_clean()}\n")

for i in range(50):
    with open(f'/home/user/data/evil/evil_{i}.fasta', 'w') as f:
        f.write(f">evil_{i}\n")
        if i < 15:
            # invalid char
            seq = list(make_clean())
            seq[10] = 'X'
            f.write("".join(seq) + "\n")
        elif i < 30:
            # too short
            f.write(make_clean(15) + "\n")
        elif i < 40:
            # too long
            f.write(make_clean(550) + "\n")
        else:
            # high GC
            seq = []
            for _ in range(100):
                if random.random() < 0.7:
                    seq.append(random.choice(gc_aa))
                else:
                    seq.append(random.choice(non_gc_aa))
            f.write("".join(seq) + "\n")
EOF

    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
