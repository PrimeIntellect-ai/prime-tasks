#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git expect socat logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app
    mkdir -p /home/user/logs

    # Create the backend legacy server
    cat << 'EOF' > /app/backend.py
import socket

def run_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8888))
    server.listen(5)
    while True:
        try:
            client, addr = server.accept()
            client.sendall(b"LOGIN:\n")
            client.recv(1024)
            client.sendall(b"PASSWORD:\n")
            client.recv(1024)
            client.sendall(b"READY>\n")
            while True:
                data = client.recv(1024)
                if not data: break
                if b"LOGOUT" in data:
                    break
                client.sendall(b"OK\n")
            client.close()
        except:
            pass

if __name__ == '__main__':
    run_server()
EOF
    chmod +x /app/backend.py

    # Create the oracle converter
    cat << 'EOF' > /app/oracle_converter.py
import sys
import re

for line in sys.stdin:
    line = line.strip()
    if line.startswith("COMMIT:"):
        print(f"TRANSACTION START {line[7:]}")
    elif line.startswith("AUTHOR:"):
        print(f"SET_USER {line[7:]}")
    else:
        m = re.match(r'^([AMD])\s+(.+)$', line)
        if m:
            op = m.group(1)
            f = m.group(2)
            if op == 'A': print(f"FILE_ADD {f}")
            elif op == 'M': print(f"FILE_MOD {f}")
            elif op == 'D': print(f"FILE_DEL {f}")
EOF
    chmod +x /app/oracle_converter.py

    chmod -R 777 /home/user
    chmod -R 777 /app
