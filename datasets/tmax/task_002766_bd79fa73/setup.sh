#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/target_service.py
import socket
import sys

HOST = '127.0.0.1'
PORT = 8077
FLAG = "FLAG{s3cc0mp_evas10n_m4st3r}\n"

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen()
    while True:
        conn, addr = s.accept()
        with conn:
            data = conn.recv(1024)
            if data == b"AUTH: REDTEAM\n":
                conn.sendall(FLAG.encode())
            else:
                conn.sendall(b"DENIED\n")
        break
EOF

    chmod -R 777 /home/user
