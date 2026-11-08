#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/vocab.txt
fast 10
linear 20
model 30
slow 5
deep 40
network 50
EOF

    cat << 'EOF' > /home/user/data/experiments.jsonl
{"experiment_id": "exp1", "desc": "fast linear model", "baseline_score": 60.0}
{"experiment_id": "exp2", "desc": "deep network", "baseline_score": 118.0}
{"experiment_id": "exp3", "desc": "slow deep model", "baseline_score": 63.0}
{"experiment_id": "exp4", "desc": "unknown architecture missing metrics", "baseline_score": 0.0}
EOF

    cat << 'EOF' > /home/user/data/metrics.jsonl
{"experiment_id": "exp1", "weights": [1.0, 1.0, 1.0, 1.0, 1.0]}
{"experiment_id": "exp2", "weights": [0.5, 2.0, 0.0, 0.0, 0.0]}
{"experiment_id": "exp3", "weights": [2.0, 0.5, 1.0, 0.0, 0.0]}
{"experiment_id": "exp5", "weights": [1.0, 1.0, 1.0, 1.0, 1.0]}
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
