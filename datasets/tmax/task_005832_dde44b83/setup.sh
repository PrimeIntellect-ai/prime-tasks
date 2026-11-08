#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/solution

    # Create the binary memory dump
    API_KEY_VAL="aB9xP2mQ5wL8vR4z"
    dd if=/dev/urandom of=/home/user/app/crash_mem.bin bs=1K count=10 2>/dev/null
    echo -n "API_KEY=${API_KEY_VAL}" >> /home/user/app/crash_mem.bin
    dd if=/dev/urandom bs=1K count=10 2>/dev/null >> /home/user/app/crash_mem.bin

    # Create the buggy report.py
    cat << 'EOF' > /home/user/app/report.py
import math

def generate_report():
    # Transactions that add up to 0.3
    t1 = 0.1
    t2 = 0.2
    expected_total = 0.3

    # Bug: Direct floating point comparison
    if t1 + t2 == expected_total:
        print("REPORT_VALID")
    else:
        print("REPORT_CRASH: Precision error")

if __name__ == "__main__":
    generate_report()
EOF

    chmod -R 777 /home/user
