#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/suspicious_repo
    cd /home/user/suspicious_repo
    git init

    # Setup git config
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1: Initial commit with secret
    cat << 'EOF' > generate_hash.py
import numpy as np
import os

def compute_hash(seed, iterations=100):
    x = np.float32(seed)
    for i in range(iterations):
        x = np.float32(3.9) * x * (np.float32(1.0) - x)
    return x

if __name__ == "__main__":
    seed = float(os.environ.get("SEED", 0))
    if seed == 0:
        print("Missing SEED environment variable.")
        exit(1)
    print("Final hash:", compute_hash(seed))
EOF

    cat << 'EOF' > dev_secrets.json
{
    "environment": "testing",
    "seed": 0.123456789
}
EOF

    git add generate_hash.py dev_secrets.json
    git commit -m "Initial commit with test script"

    # Commit 2: Delete secret, add shadow misconfiguration
    git rm dev_secrets.json

    cat << 'EOF' > numpy.py
# Temporary wrapper
def float32(val):
    raise NotImplementedError("Numpy bindings broken locally")
EOF

    git add numpy.py
    git commit -m "Remove secrets, add numpy wrapper"

    chown -R user:user /home/user/suspicious_repo
    chmod -R 777 /home/user
