#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth.log
Jan 15 10:00:01 server sshd[1234]: Failed password for root from 10.0.0.5 port 22 ssh2
Jan 15 10:01:01 server sshd[1235]: Failed password for admin from 192.168.1.50 port 22 ssh2
Jan 15 10:05:05 server sshd[1236]: Failed password for admin from 192.168.1.50 port 22 ssh2
Jan 15 10:05:10 server sshd[1237]: Failed password for admin from 192.168.1.50 port 22 ssh2
Jan 15 10:05:15 server sshd[1238]: Failed password for admin from 192.168.1.50 port 22 ssh2
Jan 15 10:06:01 server sshd[1239]: Accepted password for user from 10.0.0.5 port 22 ssh2
Jan 15 10:07:01 server sshd[1240]: Failed password for invaliduser from 172.16.0.10 port 22 ssh2
Jan 15 10:08:01 server sshd[1241]: Failed password for root from 172.16.0.10 port 22 ssh2
EOF

    mkdir -p /home/user/webroot/uploads
    touch /home/user/webroot/index.html
    touch /home/user/webroot/config.php
    touch /home/user/webroot/style.css
    touch /home/user/webroot/uploads/backdoor.php
    touch /home/user/webroot/uploads/image.png

    chmod -R 777 /home/user

    chmod 644 /home/user/webroot/index.html
    chmod 666 /home/user/webroot/config.php
    chmod 644 /home/user/webroot/style.css
    chmod 777 /home/user/webroot/uploads/backdoor.php
    chmod 644 /home/user/webroot/uploads/image.png
    chmod 755 /home/user/webroot/uploads
    chmod 755 /home/user/webroot
