#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import random
random.seed(42)
with open("/home/user/etl_edges.txt", "w") as f:
    for _ in range(200000):
        src = random.randint(1, 5000)
        # Introduce some heavily connected nodes
        if random.random() < 0.1:
            src = random.randint(1, 50)
        dst = random.randint(1, 50000)
        f.write(f"{src} {dst}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
