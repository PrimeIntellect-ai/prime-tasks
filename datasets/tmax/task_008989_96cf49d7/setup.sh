#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/raw_data /home/user/project_xray

    cat << 'EOF' > /tmp/gen_logs.py
import json
import gzip

logs = [
    {"timestamp": "2023-10-01T10:00:00Z", "project": "x-ray", "level": "INFO", "message": "Started scan"},
    {"timestamp": "2023-10-01T10:01:00Z", "project": "x-ray", "level": "FATAL", "message": "Radiation leak detected"},
    {"timestamp": "2023-10-01T10:02:00Z", "project": "apollo", "level": "FATAL", "message": "O2 tanks empty"},
    {"timestamp": "2023-10-01T10:03:00Z", "project": "x-ray", "level": "FATAL", "message": "Core meltdown imminent"},
    {"timestamp": "2023-10-01T10:04:00Z", "project": "x-ray", "level": "DEBUG", "message": "Flushing cache"}
]

with gzip.open('/home/user/raw_data/system_logs.gz', 'wt') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')
EOF
    python3 /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
