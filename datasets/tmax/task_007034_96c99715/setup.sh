#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'JSON' > /home/user/artifacts/exp1_train.json
{"experiment_id": "EXP-001", "phase": "train", "feature_mean": 10.5, "scaler_val": 10.5}
JSON
    cat << 'JSON' > /home/user/artifacts/exp1_test.json
{"experiment_id": "EXP-001", "phase": "test", "feature_mean": 12.0, "scaler_val": 10.5}
JSON

    cat << 'JSON' > /home/user/artifacts/exp2_train.json
{"experiment_id": "EXP-002", "phase": "train", "feature_mean": 5.2, "scaler_val": 5.2}
JSON
    cat << 'JSON' > /home/user/artifacts/exp2_test.json
{"experiment_id": "EXP-002", "phase": "test", "feature_mean": 6.8, "scaler_val": 6.8}
JSON

    cat << 'JSON' > /home/user/artifacts/exp3_train.json
{"experiment_id": "EXP-003", "phase": "train", "feature_mean": 1.1, "scaler_val": 1.1}
JSON
    cat << 'JSON' > /home/user/artifacts/exp3_test.json
{"experiment_id": "EXP-003", "phase": "test", "feature_mean": 1.5, "scaler_val": 1.1}
JSON

    cat << 'JSON' > /home/user/artifacts/exp4_train.json
{"experiment_id": "EXP-004", "phase": "train", "feature_mean": 42.0, "scaler_val": 42.0}
JSON
    cat << 'JSON' > /home/user/artifacts/exp4_test.json
{"experiment_id": "EXP-004", "phase": "test", "feature_mean": 40.0, "scaler_val": 40.0}
JSON

    cat << 'JSON' > /home/user/artifacts/invalid1.json
{"experiment_id": "EXP-005", "feature_mean": 42.0, "scaler_val": 42.0}
JSON

    cat << 'JSON' > /home/user/artifacts/invalid2.json
{"experiment_id": "EXP-006", "phase": "train", "feature_mean": "high", "scaler_val": 42.0}
JSON

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
