#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/syslog.txt
May 10 10:00:01 kernel: [    0.000000] Linux version 5.15.0
May 10 10:05:22 sshd[102]: Failed password for root from 192.168.1.15 port 22
May 10 10:05:25 sshd[102]: Failed password for invalid user admin from 10.0.5.99 port 22 ssh2
May 10 10:06:00 bash[200]: command logged: echo "-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD+L8M5X/w1...
-----END OPENSSH PRIVATE KEY-----" > /tmp/key
May 10 10:07:00 sshd[105]: Failed password for bob from 192.168.1.15 port 22
May 10 10:08:15 sshd[108]: Accepted publickey for dev from 10.0.5.100 port 22
May 10 10:10:00 bash[205]: command logged: cat /root/.ssh/id_ed25519
-----BEGIN OPENSSH PRIVATE KEY-----
xyz123abc...
-----END OPENSSH PRIVATE KEY-----
May 10 10:12:00 systemd[1]: Started cron utility.
EOF

    chmod -R 777 /home/user
