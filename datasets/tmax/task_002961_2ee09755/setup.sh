#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/logs/service_a
    mkdir -p /home/user/logs/service_b/nested
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/logs/service_a/app.jsonl
{"timestamp":"2023-10-01T10:00:00Z","level":"INFO","message":"Started"}
{"timestamp":"2023-10-01T10:01:00Z","level":"CRITICAL","message":"DB Connection Lost"}
{"timestamp":"2023-10-01T10:02:00Z","level":"WARN","message":"Retrying"}
{"timestamp":"2023-10-01T10:03:00Z","level":"CRITICAL","message":"Out of Memory"}
{"timestamp":"2023-10-01T10:04:00Z","level":"CRITICAL","message":"CPU Spiking"}
{"timestamp":"2023-10-01T10:05:00Z","level":"INFO","message":"Recovered"}
{"timestamp":"2023-10-01T10:06:00Z","level":"CRITICAL","message":"Network unreachable"}
{"timestamp":"2023-10-01T10:07:00Z","level":"CRITICAL","message":"Disk full"}
{"timestamp":"2023-10-01T10:08:00Z","level":"CRITICAL","message":"Service crashed"}
EOF

    cat << 'EOF' > /home/user/logs/service_b/nested/web.csv
timestamp,status,endpoint,latency
2023-10-01T10:00:00Z,OK,/api/v1/users,45
2023-10-01T10:01:00Z,ERROR,/api/v1/users,5000
2023-10-01T10:02:00Z,OK,/api/v1/health,12
2023-10-01T10:03:00Z,ERROR,/api/v1/data,4001
2023-10-01T10:04:00Z,ERROR,/api/v1/data,4005
2023-10-01T10:05:00Z,ERROR,/api/v1/auth,3000
2023-10-01T10:06:00Z,OK,/api/v1/auth,45
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
