#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/run_1.jsonl
{"experiment_id": "EXP_ALPHA", "epoch": 0, "val_loss": 2.0}
{"experiment_id": "EXP_ALPHA", "epoch": 1, "val_loss": 1.5}
{"experiment_id": "EXP_ALPHA", "epoch": 2, "val_loss": -0.5, "note": "invalid negative loss"}
{"experiment_id": "EXP_ALPHA", "epoch": 3, "val_loss": 1.2}
{"experiment_id": "EXP_ALPHA", "epoch": 4, "val_loss": "NaN", "note": "invalid type"}
{"experiment_id": "EXP_ALPHA", "epoch": 5, "val_loss": 1.0}
EOF

    cat << 'EOF' > /home/user/raw_logs/run_2.jsonl
{"experiment_id": "EXP_BETA", "epoch": 10, "val_loss": 0.8}
{"experiment_id": "EXP_BETA", "epoch": 1, "val_loss": 1.0, "note": "out of order"}
{"experiment_id": "EXP_BETA", "epoch": 2, "val_loss": 0.9}
{"experiment_id": "EXP_BETA", "epoch": -1, "val_loss": 0.5, "note": "invalid epoch"}
EOF

    chmod -R 777 /home/user
