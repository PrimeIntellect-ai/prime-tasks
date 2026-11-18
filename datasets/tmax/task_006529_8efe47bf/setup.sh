#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    python3 -c '
import random
random.seed(123)
with open("/home/user/data/raw_features.csv", "w") as f:
    for i in range(1, 1001):
        x1 = round(random.uniform(-5, 5), 4)
        x2 = round(random.uniform(-5, 5), 4)
        x3 = round(random.uniform(-5, 5), 4)
        f.write(f"u{i},{x1},{x2},{x3}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
