#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3
    pip3 install pytest

    mkdir -p /home/user/processor

    cat << 'EOF' > /home/user/telemetry.jsonl
{"id": "1", "timestamp": "2023-10-01T10:00:00Z", "locale": "en-US", "latency_ms": 45.2}
{"id": "2", "timestamp": "2023-10-01T10:00:01Z", "locale": "es-MX", "latency_ms": 100.0}
{"id": "3", "timestamp": "2023-10-01T10:00:02Z", "locale": "es-MX", "latency_ms": 150.0}
{"id": "bad-1", "timestamp": "2023-10-01T10:00:03Z", "locale": "es-MX", "latency_ms": 99.9, "error": "bad unicode \uZZZZ"}
{"id": "4", "timestamp": "2023-10-01T10:00:04Z", "locale": "fr-FR", "latency_ms": 80.1}
{"id": "5", "timestamp": "2023-10-01T10:00:05Z", "locale": "es-MX", "latency_ms": 200.0}
{"id": "6", "timestamp": "2023-10-01T10:00:06Z", "locale": "es-MX", "latency_ms": 110.0}
{"id": "bad-2", "timestamp": "2023-10-01T10:00:07Z", "locale": "es-MX", "latency_ms": 10.0, "bad_field": "val\u00"}
{"id": "7", "timestamp": "2023-10-01T10:00:08Z", "locale": "es-MX", "latency_ms": 140.0}
{"id": "8", "timestamp": "2023-10-01T10:00:09Z", "locale": "es-MX", "latency_ms": 100.0}
{"id": "9", "timestamp": "2023-10-01T10:00:10Z", "locale": "es-MX", "latency_ms": 160.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
