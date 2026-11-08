#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logs.jsonl
{"exp_id": "exp_1", "description": "resnet cnn with adam and dropout", "learning_rate": 0.001, "batch_size": 32, "accuracy": 0.85}
{"exp_id": "exp_2", "description": "cnn sgd no dropout", "learning_rate": 0.01, "batch_size": 64, "accuracy": 0.78}
{"exp_id": "exp_3", "description": "resnet adam", "learning_rate": 0.002, "batch_size": 32, "accuracy": 0.88}
{"exp_id": "exp_4", "description": "dropout sgd", "learning_rate": 0.005, "batch_size": 16, "accuracy": 0.81}
{"exp_id": "exp_failed", "description": "resnet adam with dropout", "learning_rate": 0.001, "batch_size": 32, "accuracy": 0.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
