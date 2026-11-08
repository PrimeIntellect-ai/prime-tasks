#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    # Create initial files
    mkdir -p /home/user
    python3 -c '
import os
import numpy as np

os.makedirs("/home/user", exist_ok=True)
np.random.seed(42)
seq1 = "".join(np.random.choice(list("ACGT"), 1000))
seq2 = "".join(np.random.choice(list("ACGT"), 1000))

with open("/home/user/seq1.txt", "w") as f:
    f.write(seq1)

with open("/home/user/seq2.txt", "w") as f:
    f.write(seq2)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
