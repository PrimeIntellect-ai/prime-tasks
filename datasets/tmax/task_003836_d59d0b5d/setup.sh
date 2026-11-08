#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/auth.log
Jan 15 10:00:01 server sshd[1234]: Failed password for invalid user admin@example.com from 192.168.1.100 port 50000 ssh2
Jan 15 10:05:00 server sshd[1235]: Failed password for root from 10.0.0.5 port 50001 ssh2
Jan 15 10:10:00 server sshd[1236]: Accepted publickey for alice from 192.168.1.50 port 50002 ssh2
Jan 15 10:15:00 server sshd[1237]: Invalid user bob from 10.0.0.6
Jan 15 10:20:00 server sshd[1238]: Failed password for secret_password123 from 10.0.0.7 port 50003 ssh2
Jan 15 10:25:00 server sshd[1239]: Invalid user test@domain.local from 192.168.1.101
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
    chmod 644 /home/user/auth.log
