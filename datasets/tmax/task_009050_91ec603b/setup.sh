#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "metric_id": "CPU_Load", "value": 45.2, "message": "Démarrage du système"}
{"timestamp": "2023-10-01T10:05:00Z", "metric_id": "mem_usage", "value": 1024.5, "message": "正常"}
{"timestamp": "2023-10-01T10:00:00Z", "metric_id": "cpu_load", "value": 46.1, "message": "Démarrage du système (retry)"}
{"timestamp": "2023-10-01T10:10:00Z", "metric_id": "Disk_IO", "value": 15.0, "message": "Lecture"}
{"timestamp": "2023-10-01T10:05:00Z", "metric_id": "MEM_USAGE", "value": 1024.5, "message": "正常 (retry)"}
{"timestamp": "2023-10-01T10:15:00Z", "metric_id": "cpu_load", "value": 50.0, "message": "En charge"}
{"timestamp": "2023-10-01T10:10:00Z", "metric_id": "disk_io", "value": 18.2, "message": "Lecture (final)"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
