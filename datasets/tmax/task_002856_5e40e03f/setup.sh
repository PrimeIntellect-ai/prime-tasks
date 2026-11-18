#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_audit/data
    mkdir -p /home/user/app_audit/config

    echo "print('hello')" > /home/user/app_audit/script1.py
    echo "import os" > /home/user/app_audit/data/script2.py
    echo "print('secure')" > /home/user/app_audit/secure.py

    cat << 'EOF' > /home/user/app_audit/network_policy.json
{
  "firewall": [
    "ALLOW INBOUND TCP 80",
    "DENY INBOUND TCP 22"
  ],
  "csp": [
    "default-src 'self'; script-src 'self'",
    "script-src 'none'; object-src 'none'",
    "default-src https:; img-src 'self'",
    "frame-ancestors 'none'; upgrade-insecure-requests"
  ]
}
EOF

    chmod -R 777 /home/user

    # Restore specific permissions required by the task
    chmod 777 /home/user/app_audit/script1.py
    chmod 666 /home/user/app_audit/data/script2.py
    chmod 644 /home/user/app_audit/secure.py
    chmod 644 /home/user/app_audit/network_policy.json
