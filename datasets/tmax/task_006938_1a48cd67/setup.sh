#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/scripts/backup_service.py
import os
import subprocess
import sys

def run_backup(target_dir, token):
    print("Starting backup...")
    # Vulnerability 1: Credential Leakage (token in list)
    subprocess.run(["/usr/local/bin/backup_agent", "--auth", token, target_dir])
    print("Backup finished.")

if __name__ == "__main__":
    run_backup("/var/www", "super_secret_token_123")
EOF

    cat << 'EOF' > /home/user/scripts/user_mgmt.py
import os

def create_user(username):
    # Vulnerability 2: Command Injection
    os.system(f"useradd -m {username}")

def set_password(username, password):
    # Vulnerability 3: Credential Leakage (password in f-string) & Command Injection
    os.system(f"echo '{username}:{password}' | chpasswd")

if __name__ == "__main__":
    create_user("newdev")
    set_password("newdev", "P@ssw0rd!")
EOF

    cat << 'EOF' > /home/user/scripts/safe_util.py
import subprocess

def ping_host(host):
    # Safe usage
    subprocess.run(["ping", "-c", "4", host])

if __name__ == "__main__":
    ping_host("8.8.8.8")
EOF

    chmod -R 755 /home/user/scripts
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
