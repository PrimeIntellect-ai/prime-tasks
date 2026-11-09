#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/exp1.json
{"id": 1, "notes": "Model trained well. High accuracy.", "metrics": {"accuracy": 0.95, "loss": 0.05}}
EOF

    cat << 'EOF' > /home/user/experiments/exp2.json
{"id": 2, "notes": "Model overfit. low accuracy, high loss.", "metrics": {"accuracy": 0.70, "loss": 0.80}}
EOF

    cat << 'EOF' > /home/user/experiments/exp3.json
{"id": 3, "notes": "Model trained is stable. Good accuracy.", "metrics": {"accuracy": 0.90, "loss": 0.15}}
EOF

    cat << 'EOF' > /home/user/experiments/exp4.json
{"id": 4, "notes": "Training failed. Model exploded.", "metrics": {"accuracy": 0.10, "loss": 5.00}}
EOF

    cat << 'EOF' > /home/user/experiments/exp5.json
{"id": 5, "notes": "Model trained perfectly. Excellent accuracy.", "metrics": {"accuracy": 0.92, "loss": 0.08}}
EOF

    chmod -R 777 /home/user
