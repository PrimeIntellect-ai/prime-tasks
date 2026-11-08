#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.jsonl
{"model_id": "m1", "config_string": "alpha", "latency_ms": 50, "accuracy": 0.92}
{"model_id": "m2", "config_string": "beta", "latency_ms": null, "accuracy": 0.95}
{"model_id": "m3", "config_string": "gamma", "latency_ms": 12, "accuracy": 0.88}
{"model_id": "m4", "config_string": "delta", "latency_ms": 40, "accuracy": 0.91}
{"model_id": "m5", "config_string": "epsilon", "latency_ms": 300, "accuracy": 0.99}
{"model_id": "m6", "config_string": "zeta", "latency_ms": 45, "accuracy": 0.94}
{"model_id": "m7", "config_string": "eta", "latency_ms": 60, "accuracy": 0.96}
{"model_id": "m8", "config_string": "theta", "latency_ms": 55, "accuracy": 0.93}
{"model_id": "m9", "config_string": "iota", "latency_ms": 35, "accuracy": 0.90}
{"model_id": "m10", "config_string": "kappa", "latency_ms": 28, "accuracy": 0.91}
{"model_id": "m11", "config_string": "lambda", "latency_ms": 400, "accuracy": 0.97}
EOF

    chmod -R 777 /home/user
