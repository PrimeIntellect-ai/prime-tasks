#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_logs.jsonl
{"timestamp":"2023-10-12T14:30:00+02:00","ip_address":"192.168.1.45","user_email":"alice.smith@example.com","url":"https://api.example.com/v1/users?id=1","response_time_ms":45}
{"timestamp":"12/Oct/2023:12:30:00 +0000","ip_address":"10.0.0.5","user_email":"bob@work.org","url":"http://internal.net/reports/q3","response_time_ms":150}
{"timestamp":"2023-10-12T08:30:00-04:00","ip_address":"172.16.254.1","user_email":"charlie.brown@test.io","url":"https://example.com/","response_time_ms":600}
{"timestamp":"12/Oct/2023:05:30:00 -0700","ip_address":"8.8.8.8","user_email":"admin@sys.local","url":"https://api.example.com/v1/status","response_time_ms":99}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
