#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect cargo rustc build-essential gawk sed grep
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/legacy_monitor.py
import sys
import time

def main():
    sys.stdout.write("Enter cluster name: ")
    sys.stdout.flush()
    cluster = sys.stdin.readline().strip()

    sys.stdout.write("Enter days of history: ")
    sys.stdout.flush()
    days = sys.stdin.readline().strip()

    print("=== MONITORING SYSTEM V1.0 ===")
    print(f"Connecting to {cluster} for {days} days...")
    print("STATUS: OK")
    print("-------------------------")
    print("[WARN] | Disregarding incomplete data")
    print("[INFO] | node-alpha | CPU: 50.0 | MEM: 2000.0")
    print("[INFO] | node-beta | CPU: 80.0 | MEM: 4000.0")
    print("[INFO] | node-alpha | CPU: 60.0 | MEM: 2400.0")
    print("[INFO] | node-beta | CPU: 90.0 | MEM: 4200.0")
    print("-------------------------")
    print("=== END OF REPORT ===")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/legacy_monitor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
