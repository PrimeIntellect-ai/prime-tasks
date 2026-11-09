#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments
    mkdir -p /home/user/report

    # Valid 1
    cat << 'EOF' > /home/user/experiments/exp_001.json
{"experiment_id": "001", "learning_rate": 0.01, "batch_size": 32, "schema_hash": "A1B2", "model_weights_hash": "W_ALPHA", "accuracy": 0.95}
EOF

    # Valid 2
    cat << 'EOF' > /home/user/experiments/exp_002.json
{"experiment_id": "002", "learning_rate": 0.02, "batch_size": 64, "schema_hash": "A1B2", "model_weights_hash": "W_BETA", "accuracy": 0.96}
EOF

    # Invalid (Missing batch_size)
    cat << 'EOF' > /home/user/experiments/exp_003.json
{"experiment_id": "003", "learning_rate": 0.05, "schema_hash": "C3D4", "model_weights_hash": "W_GAMMA", "accuracy": 0.90}
EOF

    # Valid 4 (Reproducibility violation with exp_001)
    cat << 'EOF' > /home/user/experiments/exp_004.json
{"experiment_id": "004", "learning_rate": 0.01, "batch_size": 32, "schema_hash": "A1B2", "model_weights_hash": "W_DELTA", "accuracy": 0.94}
EOF

    # Invalid (Missing model_weights_hash)
    cat << 'EOF' > /home/user/experiments/exp_005.json
{"experiment_id": "005", "learning_rate": 0.01, "batch_size": 16, "schema_hash": "E5F6", "accuracy": 0.88}
EOF

    # Reference
    cat << 'EOF' > /home/user/experiments/exp_ref.json
{"experiment_id": "ref", "learning_rate": 0.015, "batch_size": 60, "schema_hash": "A1B2", "model_weights_hash": "W_REF", "accuracy": 0.95}
EOF

    chmod -R 777 /home/user
