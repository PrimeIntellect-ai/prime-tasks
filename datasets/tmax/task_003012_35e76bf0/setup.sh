#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.log
Jan 15 10:00:01 server sshd[1001]: Failed password for root from 192.168.1.100 port 22 ssh2
Jan 15 10:05:01 server sshd[1002]: Accepted publickey for user from 192.168.1.50 port 22 ssh2
Jan 15 10:10:01 server sshd[1003]: Failed password for admin from 10.0.0.5 port 22 ssh2
Jan 15 10:15:01 server sshd[1004]: Failed password for root from 192.168.1.100 port 22 ssh2
Jan 15 10:20:01 server sshd[1005]: Failed password for root from 192.168.1.100 port 22 ssh2
Jan 15 10:25:01 server sshd[1006]: Failed password for root from 192.168.1.100 port 22 ssh2
Jan 15 10:30:01 server sshd[1007]: Failed password for admin from 10.0.0.5 port 22 ssh2
Jan 15 10:35:01 server sshd[1008]: Failed password for admin from 10.0.0.5 port 22 ssh2
Jan 15 10:40:01 server sshd[1009]: Failed password for admin from 10.0.0.5 port 22 ssh2
Jan 15 10:45:01 server sshd[1010]: Failed password for root from 172.16.0.2 port 22 ssh2
EOF

    cat << 'EOF' > /home/user/logs/sshd_config_old
# Standard config
Port 22
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
EOF

    chmod -R 777 /home/user
