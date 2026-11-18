#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/nginx /home/user/backend

    cat << 'EOF' > /home/user/nginx/nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:8081;
    }
}
EOF

    cat << 'EOF' > /home/user/backend/server.py
import os
import sys

if os.path.getsize('/home/user/backend/data.db') > 1024 * 1024:
    print("Error: Storage quota exceeded.")
    sys.exit(1)

if os.environ.get("TZ") != "Europe/London":
    print("Error: Invalid or missing TZ environment variable.")
    sys.exit(1)

pin = input("Enter start PIN: ")
if pin.strip() != "8573":
    print("Error: Invalid PIN.")
    sys.exit(1)

print("Backend successfully started on port 8080")
sys.exit(0)
EOF

    dd if=/dev/zero of=/home/user/backend/data.db bs=1M count=2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
