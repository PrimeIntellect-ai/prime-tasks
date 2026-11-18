#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/microservices
    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/backup

    cat << 'EOF' > /app/microservices/generator.py
#!/usr/bin/env python3
import os

os.makedirs("/home/user/data/raw", exist_ok=True)
os.makedirs("/home/user/data/backup", exist_ok=True)
for i in range(5000):
    with open(f"/home/user/data/raw/file_{i}.txt", "w") as f:
        f.write("DUMMY LOG DATA" * 10)
EOF
    chmod +x /app/microservices/generator.py

    cat << 'EOF' > /app/microservices/cli_admin.py
#!/usr/bin/env python3
import sys
pwd = input("Enter admin password: ")
if pwd != "admin123":
    print("Invalid password")
    sys.exit(1)
confirm = input("Confirm restore? (y/n): ")
if confirm.lower() != 'y':
    print("Aborted")
    sys.exit(1)
print("Restore successful")
sys.exit(0)
EOF
    chmod +x /app/microservices/cli_admin.py

    cat << 'EOF' > /home/user/backup_service.py
#!/usr/bin/env python3
import os
import gzip
import time

RAW_DIR = "/home/user/data/raw"
BACKUP_DIR = "/home/user/data/backup"

def backup():
    if not os.path.exists(RAW_DIR):
        return
    for filename in os.listdir(RAW_DIR):
        raw_path = os.path.join(RAW_DIR, filename)
        backup_path = os.path.join(BACKUP_DIR, filename + ".gz")
        with open(raw_path, 'rb') as f_in:
            with gzip.open(backup_path, 'wb') as f_out:
                f_out.writelines(f_in)
        os.remove(raw_path)
        time.sleep(0.003)

if __name__ == "__main__":
    backup()
EOF
    chmod +x /home/user/backup_service.py

    chmod -R 777 /home/user
    chmod -R 777 /app
