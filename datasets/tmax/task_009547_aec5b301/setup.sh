#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/bio_data
    cat << 'EOF' > /home/user/bio_data/setup.py
import random
random.seed(42)
with open("/home/user/bio_data/sequences.fasta", "w") as f:
    for i in range(1000):
        length = random.randint(50, 150)
        seq = "".join(random.choices(["A", "C", "G", "T"], weights=[0.2, 0.3, 0.3, 0.2], k=length))
        f.write(f">seq{i}\n{seq}\n")

with open("/home/user/bio_data/reference_gc.txt", "w") as f:
    f.write("0.60500\n")
EOF
    python3 /home/user/bio_data/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
