#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/gateway.log
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=/profile HTTP/1.1" 302 123
10.0.0.15 - - [10/Oct/2023:13:56:10 -0700] "GET /login?next=http://evil.com/login HTTP/1.1" 302 123
172.16.0.4 - - [10/Oct/2023:13:57:01 -0700] "GET /login?next=https://phishing.net/auth HTTP/1.1" 302 123
10.0.0.15 - - [10/Oct/2023:13:58:22 -0700] "GET /login?next=http://evil.com/login HTTP/1.1" 302 123
192.168.1.100 - - [10/Oct/2023:13:59:00 -0700] "GET /login?next=https://bad-actor.org HTTP/1.1" 200 4500
203.0.113.5 - - [10/Oct/2023:14:05:12 -0700] "GET /login?next=http://malware.com/drop HTTP/1.1" 302 123
EOF

    cat << 'EOF' > /home/user/csp.txt
default-src 'self'; script-src 'self' 'unsafe-inline'; object-src 'none'
EOF

    chmod -R 777 /home/user
