#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/flaky_service.py
import random
import time
import sys

def get_cache_file():
    return f"/tmp/syscache_{random.randint(100, 999)}.tmp"

def read_cache():
    filename = get_cache_file()
    # BUG: intermittently this file doesn't exist.
    f = open(filename, 'r')
    data = f.read()
    f.close()
    return data

def main():
    random.seed(time.time())
    if random.random() < 0.5:
        data = read_cache()
        print(f"Read: {data}")
    else:
        print("Skipped cache")

if __name__ == "__main__":
    for _ in range(5):
        main()
EOF
    chmod +x /home/user/flaky_service.py

    chmod -R 777 /home/user
