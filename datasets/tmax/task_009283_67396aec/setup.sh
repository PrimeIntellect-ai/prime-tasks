#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/logs
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/app/cred_manager.py
import os
import subprocess

# Secure database password
DB_PASS = "super_secret_admin_pass_123!"

def backup_db(db_name):
    # Vulnerable to OS Command Injection
    os.system(f"mysqldump -u admin -p{DB_PASS} {db_name} > backup.sql")

if __name__ == "__main__":
    import sys
    backup_db(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /app/status HTTP/1.1" 200 120
10.0.0.5 - - [10/Oct/2023:13:58:12 -0700] "POST /app/login HTTP/1.1" 401 55
172.16.0.4 - - [10/Oct/2023:14:02:05 -0700] "GET /app/secrets HTTP/1.1" 403 211
198.51.100.55 - - [10/Oct/2023:14:15:22 -0700] "GET /app/secrets HTTP/1.1" 200 405
192.168.1.10 - - [10/Oct/2023:14:20:00 -0700] "GET /app/status HTTP/1.1" 200 120
EOF

    touch /home/user/bin/backup_creds
    touch /home/user/bin/normal_script.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user

    # Set proper permissions after the recursive chmod
    chmod 4755 /home/user/bin/backup_creds
    chmod 0755 /home/user/bin/normal_script.sh
