#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data /home/user/templates /home/user/output

    cat << 'EOF' > /home/user/templates/host_summary.tpl
Host: {host}
Total Windows: {num_windows}

Metrics:
{metrics_list}
EOF

    cat << 'EOF' > /home/user/data/raw_metrics.jsonl
{"host": "web-01", "timestamp": "2023-06-01T01:15:00Z", "cpu_usage": 45.5, "memory_mb": 1024}
{"host": "web-01", "timestamp": 1685582700, "cpu_usage": 55.0, "memory_mb": 2048}
{"host": "web-01", "timestamp": "2023-06-01T01:15:00Z", "cpu_usage": 45.5, "memory_mb": 1024}
{"host": "web-01", "timestamp": "invalid_date", "cpu_usage": 10.0}
{"host": "web-01", "timestamp": "2023-06-01T02:05:00Z", "cpu_usage": 80.0, "memory_mb": 4096}
{"host": "db-01", "timestamp": "1685581200", "cpu_usage": 10.0, "memory_mb": 8192}
{"host": "db-01", "timestamp": "2023-06-01T01:30:00Z", "cpu_usage": 15.0, "memory_mb": 8192}
{"host": "db-01", "timestamp": "2023-06-01T01:45:00Z", "cpu_usage": null, "memory_mb": 8192}
{"timestamp": "2023-06-01T01:45:00Z", "cpu_usage": 50.0, "memory_mb": 1024}
{"host": "web-01", "timestamp": "2023-06-01T03:00:00Z", "cpu_usage": 90.5, "memory_mb": 4096}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
