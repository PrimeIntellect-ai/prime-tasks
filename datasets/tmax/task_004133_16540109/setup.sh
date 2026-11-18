#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/input

    python3 -c "
import os
import random

os.makedirs('/home/user/input', exist_ok=True)
random.seed(42)
bases = ['A', 'C', 'G', 'T']

with open('/home/user/input/sequences.fasta', 'w') as f:
    for i in range(100):
        f.write(f\">seq_{i:03d}\n\")
        seq = ''.join(random.choices(bases, k=1000))
        for j in range(0, 1000, 80):
            f.write(seq[j:j+80] + '\n')
"

    chmod -R 777 /home/user
