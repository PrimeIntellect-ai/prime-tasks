#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/repo
cd /home/user/repo
git init
git config user.name "Dev"
git config user.email "dev@example.com"

# Commit 1: Hardcoded key
cat << 'EOF' > process_data.py
import os
import sys

def fetch_data():
    api_key = "SEC_9988_xyz123"
    if api_key != "SEC_9988_xyz123":
        return []
    return ["1000000000000000.01", "1000000000000000.02", "1000000000000000.03"]

def aggregate(data):
    total = 0.0
    for val in data:
        total += float(val)
    return total

if __name__ == "__main__":
    data = fetch_data()
    total = aggregate(data)
    with open("/home/user/result.txt", "w") as f:
        f.write(f"{total:.2f}")
EOF

git add process_data.py
git commit -m "Initial working script with hardcoded key"

# Commit 2: Buggy script
cat << 'EOF' > process_data.py
import os
import sys

def fetch_data():
    api_key = os.environ.get("API_KEY", "")
    if not api_key:
        print("API_KEY missing")
        sys.exit(1)

    retries = 3
    while retries > 0:
        if api_key != "SEC_9988_xyz123":
            # BUG: infinite loop, forgot to decrement retries
            continue
        else:
            return ["1000000000000000.01", "1000000000000000.02", "1000000000000000.03"]
    return []

def aggregate(data):
    total = 0.0
    for val in data:
        # BUG: float precision loss on large numbers
        total += float(val)
    return total

if __name__ == "__main__":
    data = fetch_data()
    total = aggregate(data)
    with open("/home/user/result.txt", "w") as f:
        f.write(f"{total:.2f}")
EOF

git add process_data.py
git commit -m "Use env var for API key and add retry logic"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
