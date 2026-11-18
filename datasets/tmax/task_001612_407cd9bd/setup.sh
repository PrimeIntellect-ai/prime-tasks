#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/new_user_config.ini
[NewUser]
username = dev_intern
password = securepass
network_sandbox = yes
quota_mb = 500
assigned_ip = 10.0.0.50
EOF

    cat << 'EOF' > /home/user/bin/usermanager_cli
#!/usr/bin/env python3
import sys
import random

username = input("Enter username: ")
password = input("Enter password: ")
sandbox = input("Enable network sandbox? [y/N]: ")
quota = input("Set disk quota (in MB): ")

uid = random.randint(1000, 5000)
with open("/home/user/user_db.txt", "a") as f:
    f.write(f"{username}:{password}:{sandbox}:{quota}:{uid}\n")

print(f"User {username} created with UID {uid}.")
EOF

    cat << 'EOF' > /home/user/bin/quota_daemon.py
#!/usr/bin/env python3
import time
while True:
    time.sleep(10)
EOF

    chmod +x /home/user/bin/usermanager_cli
    chmod +x /home/user/bin/quota_daemon.py

    chmod -R 777 /home/user
