#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/vault

    cat << 'EOF' > /home/user/interactive_uploader.py
import sys
import time
import os

VAULT_DIR = "/home/user/vault"
os.makedirs(VAULT_DIR, exist_ok=True)

def main():
    while True:
        sys.stdout.write("Enter filename: ")
        sys.stdout.flush()
        filename = sys.stdin.readline().strip()
        if filename.lower() == 'exit':
            break

        sys.stdout.write("Enter size in bytes: ")
        sys.stdout.flush()
        try:
            size = int(sys.stdin.readline().strip())
        except ValueError:
            print("Invalid size")
            continue

        filepath = os.path.join(VAULT_DIR, filename)
        with open(filepath, 'wb') as f:
            f.write(os.urandom(size))

        sys.stdout.write("Upload complete. Enter filename or type exit: ")
        sys.stdout.flush()
        time.sleep(1) # simulate processing delay

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
