#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graphs

    # Create graph_0.txt (Analytical star graph)
    python3 -c '
with open("/home/user/graphs/graph_0.txt", "w") as f:
    for i in range(1, 21):
        f.write(f"0 {i} {1.0 / (2**i)}\n")
'

    # Create random graphs 1 to 5
    python3 -c '
import random
random.seed(42)
for g in range(1, 6):
    with open(f"/home/user/graphs/graph_{g}.txt", "w") as f:
        for i in range(50):
            w = random.uniform(0.000001, 100.0)
            f.write(f"{random.randint(0, 10)} {random.randint(0, 10)} {w:.15f}\n")
'

    chmod -R 777 /home/user
