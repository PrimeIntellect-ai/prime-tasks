#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs
    cat << 'EOF' > /home/user/raw_logs/server.log
Jan 15 10:10:00 vps1 systemd[1]: Started System Logging Service.
Jan 15 10:15:22 vps1 sshd[1234]: Failed password for invalid user admin from 192.168.1.50 port 54321 ssh2
Jan 15 10:16:01 vps1 app[555]: Connection established from 10.0.0.2
Jan 15 10:17:10 vps1 sshd[1235]: Failed password for root from 10.0.0.5 port 2222 ssh2
Jan 15 10:18:05 vps1 sshd[1236]: Accepted publickey for user1 from 192.168.1.100 port 3333 ssh2
Jan 15 10:20:00 vps1 sshd[1237]: Failed password for invalid user testuser from 172.16.0.4 port 1234 ssh2
EOF

    chmod -R 777 /home/user
