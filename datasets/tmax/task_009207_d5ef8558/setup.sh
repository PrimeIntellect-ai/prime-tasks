#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps netcat-openbsd gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    SOCK_PATH="/home/user/backend_$(date +%s)_$RANDOM.sock"

    cat << LOG > /home/user/service.log
[WARN] Deprecated configuration file used.
[INFO] Initializing subsystems...
[INFO] Backend listening on unix socket: /home/user/backend_old_1.sock
[ERROR] Failed to bind, retrying...
[INFO] Backend listening on unix socket: $SOCK_PATH
[INFO] Ready to accept connections.
LOG

    cat << 'PYEOF' > /home/user/mock_backend.py
import socket
import sys
import os

sock_path = sys.argv[1]
if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(5)

while True:
    try:
        conn, addr = server.accept()
        data = conn.recv(1024)
        if b"PING" in data:
            conn.sendall(b"PONG_SUCCESS_8472\n")
        else:
            conn.sendall(b"INVALID\n")
        conn.close()
    except Exception:
        pass
PYEOF

    # Create a startup script that will be sourced when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-start-backend.sh
if ! pgrep -f mock_backend.py > /dev/null; then
    SOCK_PATH=$(awk '/Backend listening on unix socket:/ {print $NF}' /home/user/service.log | tail -n 1)
    python3 /home/user/mock_backend.py "$SOCK_PATH" >/dev/null 2>&1 &
    sleep 0.5
fi
EOF

    chmod -R 777 /home/user
