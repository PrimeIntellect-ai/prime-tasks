#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_a.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "req_id": "a1", "latency_s": 0.1}
{"timestamp": "2023-10-01T10:00:05Z", "req_id": "a2", "latency_s": 0.2}
{"timestamp": "2023-10-01T10:00:15Z", "req_id": "a3", "latency_s": 0.9}
{"timestamp": "2023-10-01T10:00:20Z", "req_id": "a4", "latency_s": 0.8}
EOF

    cat << 'EOF' > /home/user/logs/service_b.csv
timestamp,req_id,latency_ms
2023-10-01T10:00:02Z,b1,100
2023-10-01T10:00:07Z,a2,800
2023-10-01T10:00:12Z,b2,120
2023-10-01T10:00:15Z,b3,900
2023-10-01T10:00:17Z,b3,900
2023-10-01T10:00:25Z,b4,800
EOF

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
