#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_fasta.py
import random
random.seed(42)

aas = "ACDEFGHIKLMNPQRSTVWY"

with open("/home/user/sequences.fasta", "w") as f:
    for i in range(50):
        seq = "".join(random.choices(aas, k=50))
        f.write(f">GroupA_{i}\n{seq}\n")
    for i in range(50):
        # Group B has slightly higher values
        seq = "".join(random.choices(aas, weights=[1]*10 + [2]*10, k=50))
        f.write(f">GroupB_{i}\n{seq}\n")
EOF
    python3 /tmp/setup_fasta.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
