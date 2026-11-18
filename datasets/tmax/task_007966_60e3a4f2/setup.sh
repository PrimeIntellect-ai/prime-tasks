#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/shared_data

    cat << 'EOF' > /home/user/registry_cli.py
#!/usr/bin/env python3
import sys
import time

def main():
    print("Welcome to MicroRegistry v1.0")
    user = input("Username: ")
    if user != "admin":
        print("Access denied.")
        sys.exit(1)

    pwd = input("Password: ")
    if pwd != "micro_pass_42":
        print("Access denied.")
        sys.exit(1)

    while True:
        try:
            cmd = input("registry> ")
            if cmd == "get-failing-nodes":
                print("10.0.5.12")
                print("10.0.5.19")
                print("10.0.5.24")
            elif cmd == "exit":
                print("Goodbye.")
                break
            else:
                print("Unknown command.")
        except EOFError:
            break

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/registry_cli.py

    cat << 'EOF' > /home/user/network.log
2023-10-01T12:00:01 10.0.5.12 CONNECTION_REFUSED ERR-503
2023-10-01T12:00:05 10.0.5.88 SUCCESS OK-200
2023-10-01T12:00:08 10.0.5.19 TIMEOUT ERR-TIMEOUT
2023-10-01T12:00:10 10.0.5.12 CONNECTION_REFUSED ERR-503
2023-10-01T12:00:15 10.0.5.24 DISCONNECTED ERR-RESET
2023-10-01T12:00:20 10.0.5.99 SUCCESS OK-200
EOF

    chmod -R 777 /home/user
