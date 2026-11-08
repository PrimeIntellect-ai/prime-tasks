#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.jsonl
{"timestamp": "2023-10-25T14:30:00Z", "event": "login_failed", "ip": "192.168.1.100", "user": "admin"}
{"timestamp": "2023-10-25T14:35:00Z", "event": "login_success", "ip": "10.0.0.5", "user": "alice"}
{"timestamp": "2023-10-25T14:40:00Z", "event": "login_failed", "ip": "192.168.1.101", "user": "bob"}
{"timestamp": "2023-10-25T14:45:00Z", "event": "login_failed", "ip": "192.168.1.102", "user": "charlie"}
EOF

    cat << 'EOF' > /home/user/logs/api.csv
timestamp,ip,endpoint,status
2023-10-25T14:29:55Z,192.168.1.100,/login,401
2023-10-25T14:29:58Z,192.168.1.100,/login,401
2023-10-25T14:30:04Z,192.168.1.100,/login,401
2023-10-25T14:35:00Z,10.0.0.5,/dashboard,200
2023-10-25T14:40:06Z,192.168.1.101,/login,401
EOF

    cat << 'EOF' > /home/user/logs/db.log
[25/Oct/2023:14:29:55 +0000] INFO: User admin accessed index
[25/Oct/2023:14:30:02 +0000] ERROR: Invalid password hash for user admin
[25/Oct/2023:14:39:58 +0000] ERROR: Connection timeout for user bob
[25/Oct/2023:14:40:01 +0000] ERROR: Rate limit exceeded for user bob
[25/Oct/2023:14:45:10 +0000] ERROR: Unknown user charlie
EOF

    chmod -R 777 /home/user
