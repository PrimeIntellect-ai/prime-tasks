#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/auth.log
10:00:01 sshd[101]: Connection from 192.168.1.50
10:00:02 sshd[101]: Offering public key: RSA SHA256:abc
10:00:02 sshd[101]: Connection closed by 192.168.1.50
10:05:01 sshd[102]: Connection from 10.0.0.5
10:05:02 sshd[102]: Offering public key: RSA SHA256:def
10:05:03 sshd[102]: Accepted publickey for user from 10.0.0.5
10:06:01 sshd[103]: Connection from 172.16.0.10
10:06:02 sshd[103]: Offering public key: RSA SHA256:ghi
10:06:02 sshd[103]: Connection closed by 172.16.0.10
EOF

    chmod -R 777 /home/user
