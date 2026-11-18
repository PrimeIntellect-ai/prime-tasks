#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect golang-go curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_cli.py
#!/usr/bin/env python3
import sys
import time

def main():
    try:
        sys.stdout.write("Username: ")
        sys.stdout.flush()
        user = sys.stdin.readline().strip()

        sys.stdout.write("Password: ")
        sys.stdout.flush()
        password = sys.stdin.readline().strip()

        if user != "admin" or password != "sre_admin_pass":
            print("Authentication failed.")
            sys.exit(1)

        sys.stdout.write("Cmd: ")
        sys.stdout.flush()
        cmd = sys.stdin.readline().strip()

        if cmd == "get_uptime":
            # Hardcoded value for verification purposes
            print("System Uptime: 86400 seconds")
        else:
            print("Unknown command.")
            sys.exit(1)

    except KeyboardInterrupt:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/legacy_cli.py
    chmod -R 777 /home/user
