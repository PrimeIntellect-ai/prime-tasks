#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.jsonl
{"exp_id": "EXP_001", "description": "ResNet50 with Adam optimizer, lr=0.001, batch_size=32", "metrics": [0.81, 0.82, 0.81]}
{"exp_id": "EXP_002", "description": "VGG16 with SGD, lr=0.01", "metrics": [0.70, 0.71, 0.69]}
{"exp_id": "EXP_003", "description": "ResNet50 using AdamW optimizer, lr=0.005, batch_size=64", "metrics": [0.85, 0.86, 0.84]}
{"exp_id": "EXP_004", "description": "MobileNet v2, Adam, lr=0.001", "metrics": [0.75, 0.76, 0.74]}
{"exp_id": "EXP_005", "description": "ResNet50 with Adam optimizer, lr=0.001, batch_size=64", "metrics": [0.83, 0.82, 0.84]}
{"exp_id": "EXP_006", "description": "DenseNet121, AdamW, learning_rate=0.001", "metrics": [0.88, 0.89, 0.87]}
EOF

    chmod -R 777 /home/user
