#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/appliance.py
#!/usr/bin/env python3
import sys
import os

def main():
    print("Welcome to EdgeRouter")
    user = input("Username: ")
    if user != "admin": return
    pwd = input("Password: ")
    if pwd != "netadmin99": return

    while True:
        try:
            cmd = input("router# ").strip()
        except EOFError:
            break

        if cmd == "check-uplink":
            if os.path.exists("/home/user/force_down"):
                print("Uplink is DOWN")
            else:
                print("Uplink is UP")
        elif cmd == "exit":
            break
        else:
            print("Unknown command")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/appliance.py

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    chmod -R 777 /home/user
