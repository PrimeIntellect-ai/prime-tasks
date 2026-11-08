#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs_json /home/user/logs_csv

    cat << 'EOF' > /home/user/logs_json/serverA.json
[
  {"time": "2023-10-01T10:00:00Z", "cpu": 40.0, "ip": "10.0.5.12"},
  {"time": "2023-10-01T10:10:00Z", "cpu": 50.0, "ip": "10.0.5.14"},
  {"time": "2023-10-01T10:15:00Z", "cpu": null, "ip": "10.0.5.15"},
  {"time": "2023-10-01T10:25:00Z", "cpu": 65.0, "ip": "10.0.5.20"}
]
EOF

    cat << 'EOF' > /home/user/logs_csv/serverB.csv
timestamp,cpu_usage,client_ip
2023-10-01T10:05:00Z,30.0,192.168.1.100
2023-10-01T10:20:00Z,,192.168.1.105
2023-10-01T10:30:00Z,70.0,192.168.1.110
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
