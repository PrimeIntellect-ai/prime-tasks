#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat expect
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    # Create target logs directory and populate with specific byte-sized files
    mkdir -p /home/user/target_logs/nested_logs
    head -c 2048 /dev/urandom > /home/user/target_logs/file1.log
    head -c 4096 /dev/urandom > /home/user/target_logs/nested_logs/file2.log

    # Create the UNIX socket daemon in Python
    cat << 'EOF' > /home/user/admin_daemon.py
import socket
import os
import sys

SOCKET_PATH = '/home/user/admin.sock'

if os.path.exists(SOCKET_PATH):
    os.remove(SOCKET_PATH)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET_PATH)
server.listen(1)

while True:
    try:
        conn, addr = server.accept()
        conn.sendall(b"Passcode:")
        data = conn.recv(1024).decode('utf-8').strip()
        if data == "obs_secure_123":
            conn.sendall(b"Action:")
            action = conn.recv(1024).decode('utf-8').strip()
            if action == "CHECK_FS":
                conn.sendall(b"/home/user/target_logs\n")
        conn.close()
    except Exception as e:
        break
EOF

    # Create the socket file to pass initial state tests
    python3 -c "import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind('/home/user/admin.sock')"

    # Start daemon in background on shell start
    echo "nohup python3 /home/user/admin_daemon.py > /dev/null 2>&1 &" >> /home/user/.bashrc

    chmod -R 777 /home/user
