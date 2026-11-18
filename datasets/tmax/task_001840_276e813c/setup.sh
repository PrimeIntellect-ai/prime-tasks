#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/logs.jsonl
{"ts": "2023-10-25T14:32:45Z", "uid": "u1", "ip": "10.0.0.5", "email": "john.doe@gmail.com"}
{"ts": "2023-10-25T14:32:12Z", "uid": "u2", "ip": "192.168.1.100", "email": "sarah@yahoo.com"}
{"ts": "2023-10-25T14:35:00Z", "uid": "u1", "ip": "10.0.0.5", "email": "john.doe@gmail.com"}
{"ts": "2023-10-25T15:10:33Z", "uid": "u3", "ip": "172.16.254.1", "email": "admin@company.org"}
EOF

    cat << 'EOF' > /home/user/data/tx.csv
tx_ts,uid,amount
2023-10-25T14:32:10Z,u1,100.50
2023-10-25T14:32:59Z,u1,50.25
2023-10-25T14:32:05Z,u2,20.00
2023-10-25T15:00:00Z,u3,500.00
2023-10-25T15:10:15Z,u3,75.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
