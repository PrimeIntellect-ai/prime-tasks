#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/app /home/user/logs /home/user/data

    cat << 'EOF' > /home/user/app/backup_worker.py
import argparse
import sys
import os

def perform_backup(key):
    print("Starting backup with key length:", len(key))
    # Backup logic here
    pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--key", required=True, help="Secret backup key")
    args = parser.parse_args()

    perform_backup(args.key)
EOF

    cat << 'EOF' > /home/user/app/data_processor.py
import os
import sys

def process_data():
    db_pass = os.environ.get("DB_PASSWORD")
    if not db_pass:
        print("Missing DB password in env.")
        sys.exit(1)
    print("Processing data...")

if __name__ == "__main__":
    process_data()
EOF

    cat << 'EOF' > /home/user/logs/process.log
[2023-10-24 08:12:01] PID 1042: /usr/bin/python3 /home/user/app/data_processor.py
[2023-10-24 08:15:33] PID 1105: /bin/bash /usr/local/bin/run_healthcheck.sh
[2023-10-24 08:20:00] PID 1299: python3 /home/user/app/backup_worker.py --target /mnt/nfs/backup --key x9F2kL1pQ8zT4wR!
[2023-10-24 08:25:10] PID 1345: /usr/bin/top -b -n 1
EOF

    echo -n "DEVSECOPS_FLAG_998822" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:x9F2kL1pQ8zT4wR! -out /home/user/data/secret.enc

    chmod 755 /home/user/app/*.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
