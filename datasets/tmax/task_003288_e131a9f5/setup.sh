#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    # Create the mock server script
    cat << 'EOF' > /home/user/mock_qemu.py
import socket
import os
import threading

SOCK_FILE = "/home/user/qemu-monitor.sock"

if os.path.exists(SOCK_FILE):
    os.remove(SOCK_FILE)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCK_FILE)
server.listen(1)

def handle_client(conn):
    try:
        conn.sendall(b"login: ")
        user = conn.recv(1024).decode().strip()
        conn.sendall(b"Password: ")
        pwd = conn.recv(1024).decode().strip()

        if user == "sre_admin" and pwd == "monitor123":
            conn.sendall(b"\n(qemu) ")
            while True:
                cmd = conn.recv(1024).decode().strip()
                if cmd == "info uptime":
                    conn.sendall(b"\nVM uptime: 1337 days, 04:20:00\n(qemu) ")
                elif cmd == "quit":
                    break
                else:
                    conn.sendall(b"\nunknown command\n(qemu) ")
        else:
            conn.sendall(b"\nLogin incorrect\n")
    finally:
        conn.close()

def run_server():
    while True:
        conn, _ = server.accept()
        t = threading.Thread(target=handle_client, args=(conn,))
        t.daemon = True
        t.start()

t = threading.Thread(target=run_server)
t.daemon = True
t.start()

# Keep main thread alive
import time
while True:
    time.sleep(1)
EOF

    # Create the dead socket for initial state test
    python3 -c "import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind('/home/user/qemu-monitor.sock')"

    # Add to bashrc so it runs in background when agent logs in
    echo "python3 /home/user/mock_qemu.py &" >> /home/user/.bashrc

    chmod -R 777 /home/user
