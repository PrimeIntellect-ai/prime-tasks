#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.jsonl
{"model_id": "m1", "features": [0.0, 6.0, 8.0], "latency_ms": 42.5}
{"model_id": "m2", "features": [5.0, 5.0], "latency_ms": 12.0}
{"model_id": "m3", "features": [10.0, 0.0, 0.0], "latency_ms": 30.1}
{"model_id": "m4", "features": "invalid", "latency_ms": 10.0}
{"model_id": "m5", "features": [3.0, 4.0, 0.0], "latency_ms": 15.5}
{"model_id": "m6", "features": [8.0, 8.0, 8.0], "latency_ms": 55.0}
{"model_id": "m7", "features": [0.0, 10.0, 0.0], "latency_ms": 40.0}
{"model_id": "m8", "features": [2.0, 2.0, 2.0], "latency_ms": 8.0}
{"model_id": "m9", "features": [12.0, 5.0, 0.0], "latency_ms": 60.5}
{"model_id": "m10", "features": [1.0, 1.0, 1.0], "latency_ms": "fast"}
{"model_id": "m11", "features": [0.0, 0.0, 15.0], "latency_ms": 48.2}
{"model_id": "m12", "features": [1.0, 2.0, 3.0], "latency_ms": 11.1}
{"model_id": "m13", "features": [6.0, 6.0, 7.0], "latency_ms": 70.0}
{"model_id": "m14", "features": [0.0, 0.0, 0.0], "latency_ms": 5.0}
EOF

    chmod -R 777 /home/user
