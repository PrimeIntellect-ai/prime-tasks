#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    # Create directories
    mkdir -p /home/user/nginx/conf/
    mkdir -p /home/user/apps/alice/
    mkdir -p /home/user/git/alice.git/hooks/
    mkdir -p /home/user/scripts/

    # Create misconfigured nginx config
    cat << 'EOF' > /home/user/nginx/conf/alice.conf
server {
    listen 8080;
    server_name alice.example.com;

    location / {
        proxy_pass http://unix:/tmp/wrong.sock;
        proxy_set_header Host $host;
    }
}
EOF

    # Create admin tool
    cat << 'EOF' > /home/user/scripts/admin_tool.py
#!/usr/bin/env python3
import sys
import time

if len(sys.argv) != 3 or sys.argv[1] != 'unlock':
    print("Usage: admin_tool.py unlock <user>")
    sys.exit(1)

user = sys.argv[2]
pwd = input("Admin Password: ")
if pwd != "supersecret99":
    print("Auth failed")
    sys.exit(1)

conf = input(f"Confirm unlock for {user}? (y/n): ")
if conf.lower().strip() == 'y':
    with open(f"/home/user/{user}_unlocked.flag", "w") as f:
        f.write("UNLOCKED\n")
    print("Success")
    sys.exit(0)
else:
    print("Cancelled")
    sys.exit(1)
EOF

    chmod +x /home/user/scripts/admin_tool.py

    # Setup user and permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
