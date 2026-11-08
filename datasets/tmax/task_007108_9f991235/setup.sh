#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data
    cat << 'EOF' > /home/user/audit_data/access.log
192.168.1.15 - - [20/Nov/2023:14:01:00 +0000] "GET /login?redirect=/dashboard HTTP/1.1" 302 512 "session_id=a1b2c3d4"
10.0.5.22 - - [20/Nov/2023:14:02:15 +0000] "GET /login?redirect=http://malicious.com/phish HTTP/1.1" 302 512 "session_id=f9e8d7c6"
172.16.0.5 - - [20/Nov/2023:14:03:00 +0000] "GET /login?redirect=https://attacker.org/malware HTTP/1.1" 302 512 "session_id=x1y2z3w4"
192.168.1.100 - - [20/Nov/2023:14:04:10 +0000] "GET /login?redirect=http://baddomain.net HTTP/1.1" 403 256 "session_id=m5n6o7p8"
10.1.2.3 - - [20/Nov/2023:14:05:00 +0000] "GET /login?redirect=/settings HTTP/1.1" 302 512 "session_id=q9r8s7t6"
8.8.8.8 - - [20/Nov/2023:14:06:22 +0000] "GET /login?redirect=http://evil.com/steal HTTP/1.1" 302 512 "session_id=p0o9i8u7"
EOF
    chmod 644 /home/user/audit_data/access.log

    chmod -R 777 /home/user
