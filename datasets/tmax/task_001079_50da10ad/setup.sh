#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/waf.log
[2024-10-12T08:12:01] IP="192.168.1.10" USER="guest" ENDPOINT="/download" STATUS="403" WAF="BLOCK" REASON="Path Traversal Detected" PARAMS="path=../../../etc/passwd" COOKIE="session_token=gst_112233;"
[2024-10-12T08:15:33] IP="192.168.1.50" USER="admin" ENDPOINT="/download" STATUS="403" WAF="BLOCK" REASON="Path Traversal Detected" PARAMS="path=../../../etc/shadow" COOKIE="session_token=adm_8f7e6d5c4b;"
[2024-10-12T08:18:22] IP="10.0.0.22" USER="admin" ENDPOINT="/download" STATUS="200" WAF="ALLOW" REASON="Clean" PARAMS="" HEADERS="X-Bypass-Target: 2e2e2f2e2e2f2e2e2f6574632f736861646f77" COOKIE="session_token=adm_8f7e6d5c4b;"
[2024-10-12T08:20:05] IP="172.16.0.5" USER="guest" ENDPOINT="/download" STATUS="403" WAF="BLOCK" REASON="Illegal Character" PARAMS="path=../" COOKIE="session_token=gst_112233;"
EOF

    chmod -R 777 /home/user
