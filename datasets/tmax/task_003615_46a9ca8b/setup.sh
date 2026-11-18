#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backup_logs.jsonl
{"job_id": "job_a1", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 100, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_a2", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 200, "timestamp": "2023-10-01T11:00:00Z"}
{"job_id": "job_a3", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 150, "timestamp": "2023-10-01T12:00:00Z"}
{"job_id": "job_a4", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 50, "timestamp": "2023-10-01T13:00:00Z"}
{"job_id": "job_a5", "cluster": "alpha-cluster", "status": "SUCCESS", "duration_seconds": 500, "timestamp": "2023-10-01T14:00:00Z"}
{"job_id": "job_b1", "cluster": "beta-cluster", "status": "FAILED", "duration_seconds": 300, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_b2", "cluster": "beta-cluster", "status": "FAILED", "duration_seconds": 300, "timestamp": "2023-10-01T11:00:00Z"}
{"job_id": "job_c1", "cluster": "gamma-cluster", "status": "SUCCESS", "duration_seconds": 120, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_d1", "cluster": "delta-cluster", "status": "FAILED", "duration_seconds": 45, "timestamp": "2023-10-01T10:00:00Z"}
EOF

    chmod -R 777 /home/user
