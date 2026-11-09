#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mlops

    cat << 'EOF' > /home/user/experiments.csv
ID,Latency_ms,Accuracy,Description
EXP-001,45,0.92,Convolutional neural network with three layers and adam optimizer
EXP-002,30,0.85,Simple linear regression baseline
EXP-003,40,0.91,Convolutional net with 3 layers using adam
EXP-004,60,0.94,Heavy deep learning model with self attention and transformers
EXP-005,48,0.90,Conv neural net 3 layers adam opt
EXP-006,25,0.88,Decision tree classifier
EXP-007,42,0.89,Convolutional neural network with two layers and sgd
EOF

    chmod -R 777 /home/user
