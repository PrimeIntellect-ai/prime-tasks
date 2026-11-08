#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments
    cd /home/user/experiments

    cat << 'EOF' > generate.py
import os
data = [
    (0.01, 32), (0.02, 32), (0.05, 32), (0.1, 32),
    (0.01, 64), (0.02, 64), (0.05, 64), (0.1, 64),
    (0.01, 128), (0.02, 128)
]
for i, (lr, bs) in enumerate(data):
    acc = 0.90 + (lr * 1.0) - (bs * 0.001)
    with open(f"exp_{i}.log", "w") as f:
        f.write(f"Experiment ID: {i}\n")
        f.write(f"learning_rate: {lr}\n")
        f.write(f"batch_size: {bs}\n")
        f.write(f"validation_accuracy: {acc:.4f}\n")
EOF
    python3 generate.py
    rm generate.py

    cd /home/user
    tar -czf logs.tar.gz -C /home/user experiments
    rm -rf /home/user/experiments

    chmod -R 777 /home/user
