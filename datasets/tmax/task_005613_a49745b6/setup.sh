#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/proc_dump/1044
    mkdir -p /home/user/proc_dump/1045
    mkdir -p /home/user/proc_dump/1046

    cat << 'EOF' > /home/user/app_requests.log
{"timestamp": "2024-05-10T12:00:00Z", "ip": "192.168.1.15", "method": "GET", "endpoint": "/login", "headers": {"User-Agent": "Mozilla/5.0", "Cookie": "session=12345"}}
{"timestamp": "2024-05-10T12:01:22Z", "ip": "10.9.8.7", "method": "POST", "endpoint": "/trigger_job", "headers": {"User-Agent": "curl/7.68.0", "Cookie": "session=99999; auth_bypass=true"}}
{"timestamp": "2024-05-10T12:05:00Z", "ip": "172.16.0.4", "method": "GET", "endpoint": "/status", "headers": {"User-Agent": "Mozilla/5.0", "Cookie": "session=abcde"}}
EOF

    cat << 'EOF' > /home/user/backend_worker.py
import sys
import time

def process_job(db_user, db_pass):
    # Connect to database
    print(f"Connecting to DB with {db_user}...")
    time.sleep(5)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python backend_worker.py <db_user> <db_password>")
        sys.exit(1)

    process_job(sys.argv[1], sys.argv[2])
EOF

    printf "bash\0-c\0sleep 60\0" > /home/user/proc_dump/1044/cmdline
    printf "python3\0/home/user/backend_worker.py\0admin_user\0Pr0d_DB_S3cr3t_99!\0" > /home/user/proc_dump/1045/cmdline
    printf "/usr/sbin/nginx\0-g\0daemon off;\0" > /home/user/proc_dump/1046/cmdline

    chmod -R 777 /home/user
