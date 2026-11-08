#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/server_logs.csv
timestamp,ip_address,status_code,endpoint
2023-10-01T10:00:00Z,203.0.113.5,200,/index.html
2023-10-01T10:01:00Z,198.51.100.22,404,/admin
2023-10-01T10:02:00Z,198.51.100.22,500,/api/v1/data
2023-10-01T10:03:00Z,203.0.113.5,403,/config
2023-10-01T10:04:00Z,10.0.0.5,200,/health
EOF

    cat << 'EOF' > /home/user/logs/auth_logs.json
[
  {"time": "10:05", "src_ip": "198.51.100.45", "event": "login", "status": "failed"},
  {"time": "10:06", "src_ip": "203.0.113.99", "event": "login", "status": "success"},
  {"time": "10:07", "src_ip": "198.51.100.45", "event": "login", "status": "failed"},
  {"time": "10:08", "src_ip": "192.0.2.10", "event": "login", "status": "failed"},
  {"time": "10:09", "src_ip": "192.0.2.10", "event": "login", "status": "failed"}
]
EOF

    chmod -R 777 /home/user
