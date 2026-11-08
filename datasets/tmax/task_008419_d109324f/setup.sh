#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_monitor.py
import sys

healthy_services = {"web-frontend", "auth-service", "db-primary"}
down_services = {"payment-gateway", "cache-node"}

def main():
    while True:
        sys.stdout.write("Enter service name: ")
        sys.stdout.flush()
        svc = sys.stdin.readline().strip()

        if svc in healthy_services:
            print("Status: OK")
        elif svc in down_services:
            print("Status: DOWN")
        else:
            print("Status: UNKNOWN")

        sys.stdout.write("Check another? (y/n): ")
        sys.stdout.flush()
        ans = sys.stdin.readline().strip().lower()
        if ans != 'y':
            break

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/legacy_monitor.py
    chmod -R 777 /home/user
