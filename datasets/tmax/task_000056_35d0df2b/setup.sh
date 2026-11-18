#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssl
    pip3 install pytest

    mkdir -p /home/user/audit_task
    cd /home/user/audit_task

    cat << 'EOF' > raw_access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?token=aB3dE9x HTTP/1.1" 200 2326
10.0.0.5 - - [10/Oct/2023:13:56:10 -0700] "GET /product?id=1' OR '1'='1 HTTP/1.1" 500 503
172.16.0.4 - - [10/Oct/2023:13:57:00 -0700] "POST /checkout?cc=4111222233334444&item=5 HTTP/1.1" 200 405
192.168.1.11 - - [10/Oct/2023:13:58:12 -0700] "GET /../../../../etc/passwd HTTP/1.1" 403 125
10.1.1.1 - - [10/Oct/2023:13:59:00 -0700] "GET /index.html HTTP/1.1" 200 1024
192.168.1.10 - - [10/Oct/2023:14:00:00 -0700] "GET /dashboard?token=xyz987&cc=1111222233334444 HTTP/1.1" 200 2326
EOF

    dd if=/dev/urandom of=key.bin bs=1 count=32 2>/dev/null
    dd if=/dev/urandom of=iv.bin bs=1 count=16 2>/dev/null

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
