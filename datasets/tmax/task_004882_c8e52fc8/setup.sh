#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask pexpect

    mkdir -p /app

    cat << 'EOF' > /app/legacy_cli.py
#!/usr/bin/env python3
import sys
import os

print("Welcome to Legacy Data System")
try:
    username = input("Username: ")
    password = input("Password: ")

    if username != "admin" or password != "supersecret":
        print("Access Denied")
        sys.exit(1)

    print("Access Granted")
    while True:
        cmd = input("Command: ")
        if cmd.startswith("QUERY "):
            filepath = cmd.split(" ", 1)[1]
            if os.path.exists(filepath):
                with open(filepath, 'r') as f:
                    print(f.read())
            else:
                print("File not found")
        elif cmd == "EXIT":
            break
        else:
            print("Unknown command")
except EOFError:
    pass
EOF
    chmod +x /app/legacy_cli.py

    cat << 'EOF' > /app/api_gateway.py
from flask import Flask, request, jsonify

app = Flask(__name__)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
