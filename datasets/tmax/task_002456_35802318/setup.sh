#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/analytics_repo
    cd /home/user/analytics_repo

    git config --global init.defaultBranch main
    git config --global user.email "dev@example.com"
    git config --global user.name "Developer"
    git init

    # 1. Create the initial transactions file
    cat << 'EOF' > transactions.csv
0.10
0.20
0.30
100.00
10.05
0.10
0.20
EOF
    git add transactions.csv
    git commit -m "Initial commit with transactions"

    # 2. Add the secret key (to be leaked)
    cat << 'EOF' > secrets.json
{
  "encryption_key": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
}
EOF
    git add secrets.json
    git commit -m "Add config secrets"

    # 3. Remove the secret key to hide it
    git rm secrets.json
    git commit -m "Remove sensitive secrets file"

    # 4. Create the buggy process.py script
    cat << 'EOF' > process.py
import sys
import os

def check_key():
    try:
        with open('/home/user/key.txt', 'r') as f:
            key = f.read().strip()
            if key != "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4":
                sys.exit(1)
    except:
        sys.exit(1)

def check_token():
    try:
        # Strace will reveal the script trying to access this file
        with open('/home/user/.hidden_token_file', 'r') as f:
            if f.read().strip() != "TOKEN_OK":
                sys.exit(1)
    except:
        sys.exit(1)

def process_data():
    total = 0.0
    with open('transactions.csv', 'r') as f:
        for line in f:
            val = line.strip()
            if val:
                # Bug: Standard float addition causing precision errors
                total += float(val)

    with open('/home/user/total.txt', 'w') as f:
        f.write(f"Total: {total}\n")

if __name__ == "__main__":
    check_key()
    check_token()
    process_data()
EOF
    git add process.py
    git commit -m "Add process script"

    chmod -R 777 /home/user
