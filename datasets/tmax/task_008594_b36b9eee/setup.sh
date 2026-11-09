#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip locales socat
    pip3 install pytest

    # Generate the required locale
    locale-gen de_DE.UTF-8

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/server.py
import socket
import sys

def start_server():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(('127.0.0.1', 9090))
    server_socket.listen(1)

    while True:
        client_socket, _ = server_socket.accept()
        payload = """[2023-10-01 10:00:01] STATUS: 250 Delivered | TO: alice@example.com
[2023-10-01 10:05:12] STATUS: 550 Bounced | TO: charlie@bad-domain.net
[2023-10-01 10:10:05] STATUS: 250 Delivered | TO: bob@example.com
[2023-10-01 10:15:22] STATUS: 550 Bounced | TO: zack@bounced.org
[2023-10-01 10:20:00] STATUS: 550 Bounced | TO: admin@nowhere.com
[2023-10-01 10:25:00] STATUS: 450 Deferred | TO: test@test.com
"""
        client_socket.sendall(payload.encode('utf-8'))
        client_socket.close()

if __name__ == '__main__':
    start_server()
EOF

    cat << 'EOF' > /home/user/app/daemon.py
#!/usr/bin/env python3
import os
import sys
import socket

if os.environ.get('TZ') != 'Europe/Berlin':
    print("CRITICAL: Invalid Timezone. Expected Europe/Berlin.")
    sys.exit(1)

if os.environ.get('LC_TIME') != 'de_DE.UTF-8':
    print("CRITICAL: Invalid Time Locale. Expected de_DE.UTF-8.")
    sys.exit(1)

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8080))
    data = s.recv(4096).decode('utf-8')
    s.close()

    with open('/home/user/app/processed_logs.txt', 'w') as f:
        f.write(data)
    print("Service completed successfully.")
except Exception as e:
    print(f"CRITICAL: Could not connect to internal metadata server on port 8080. Error: {e}")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/app/run_service.sh
#!/bin/bash
python3 /home/user/app/daemon.py
EOF

    chmod +x /home/user/app/daemon.py
    chmod +x /home/user/app/run_service.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
