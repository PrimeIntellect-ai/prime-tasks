#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_logs.txt
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?redirect_to=/home HTTP/1.1" 200 2326 session_id=abc123xyz
10.0.0.5 - - [10/Oct/2023:13:56:10 -0700] "GET /login?redirect_to=https://evil.phish.com/login HTTP/1.1" 302 - session_id=def456uvw
172.16.0.2 - - [10/Oct/2023:13:58:22 -0700] "GET /login?redirect_to=http://malware.site/download HTTP/1.1" 302 - session_id=ghi789rst
192.168.1.11 - - [10/Oct/2023:14:01:05 -0700] "GET /login?redirect_to=/settings HTTP/1.1" 200 1542 session_id=jkl012mno
EOF

    chmod -R 777 /home/user
