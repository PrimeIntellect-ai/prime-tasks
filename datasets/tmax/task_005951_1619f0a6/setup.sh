#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect cron
pip3 install pytest

mkdir -p /home/user/bin
cat << 'EOF' > /home/user/bin/register_node.py
#!/usr/bin/env python3
import sys
node = input("Enter node name: ")
if node != "worker-01":
    sys.exit(1)
token = input("Enter auth token: ")
if token != "secret-token-99":
    sys.exit(1)
print("Registration successful")
EOF
chmod +x /home/user/bin/register_node.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
