#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backup_data.jsonl
{"backup_id": "b1", "collection": "users", "timestamp": "2023-10-01T10:00:00Z", "metrics": {"size_bytes": 100, "duration": 10, "status": "success"}}
{"backup_id": "b2", "collection": "users", "timestamp": "2023-10-02T10:00:00Z", "metrics": {"size_bytes": 100, "duration": 10, "status": "success"}}
{"backup_id": "b3", "collection": "users", "timestamp": "2023-10-03T10:00:00Z", "metrics": {"size_bytes": 100, "duration": 10, "status": "success"}}
{"backup_id": "b4", "collection": "users", "timestamp": "2023-10-04T10:00:00Z", "metrics": {"size_bytes": 100, "duration": 10, "status": "success"}}
{"backup_id": "b5", "collection": "orders", "timestamp": "2023-10-01T10:00:00Z", "metrics": {"size_bytes": 1000, "duration": 10, "status": "success"}}
{"backup_id": "b6", "collection": "orders", "timestamp": "2023-10-02T10:00:00Z", "metrics": {"size_bytes": 1100, "duration": 10, "status": "success"}}
{"backup_id": "b7", "collection": "orders", "timestamp": "2023-10-03T10:00:00Z", "metrics": {"size_bytes": 2000, "duration": 10, "status": "failed"}}
{"backup_id": "b8", "collection": "orders", "timestamp": "2023-10-04T10:00:00Z", "metrics": {"size_bytes": 1050, "duration": 10, "status": "success"}}
{"backup_id": "b9", "collection": "orders", "timestamp": "2023-10-05T10:00:00Z", "metrics": {"size_bytes": 1800, "duration": 10, "status": "success"}}
{"backup_id": "b10", "collection": "products", "timestamp": "2023-10-01T10:00:00Z", "metrics": {"size_bytes": 500, "duration": 10, "status": "success"}}
{"backup_id": "b11", "collection": "products", "timestamp": "2023-10-02T10:00:00Z", "metrics": {"size_bytes": 500, "duration": 10, "status": "success"}}
{"backup_id": "b12", "collection": "products", "timestamp": "2023-10-03T10:00:00Z", "metrics": {"size_bytes": 1200, "duration": 10, "status": "success"}}
{"backup_id": "b13", "collection": "logs", "timestamp": "2023-10-01T10:00:00Z", "metrics": {"size_bytes": 10, "duration": 10, "status": "success"}}
{"backup_id": "b14", "collection": "logs", "timestamp": "2023-10-02T10:00:00Z", "metrics": {"size_bytes": 10, "duration": 10, "status": "success"}}
{"backup_id": "b15", "collection": "logs", "timestamp": "2023-10-03T10:00:00Z", "metrics": {"size_bytes": 50, "duration": 10, "status": "success"}}
{"backup_id": "b16", "collection": "metrics", "timestamp": "2023-10-03T10:00:00Z", "metrics": {"size_bytes": 2000, "duration": 10, "status": "success"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
