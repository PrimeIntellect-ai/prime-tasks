#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/metadata.jsonl
{"experiment_id": "exp_A", "learning_rate": 0.01, "batch_size": 32, "accuracy": 0.85}
{"experiment_id": "exp_B", "learning_rate": 0.02, "batch_size": 64, "accuracy": 0.88}
{"experiment_id": "exp_C", "learning_rate": 0.005, "batch_size": 16, "accuracy": 0.82}
{"experiment_id": "exp_D", "learning_rate": 0.05, "batch_size": 128, "accuracy": 0.90}
EOF

    cat << 'EOF' > /home/user/experiments/embeddings.csv
experiment_id,v1,v2,v3
exp_A,1.0,0.0,0.0
exp_B,0.9,0.1,0.0
exp_C,0.0,1.0,0.0
exp_D,0.0,0.0,1.0
EOF

    chmod -R 777 /home/user
